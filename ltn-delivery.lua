---@class LtnSurfaceConnection
---@field entity1 LuaEntity
---@field entity2 LuaEntity
---@field network_id integer

---@class LtnDelivery
---@field train LuaTrain
---@field shipment table<string,integer>
---@field surface_connections LtnSurfaceConnection[]

local Delivery = {
	use_clearance = settings.global["se-ltn-use-elevator-clearance"].value,
	clearance_name = settings.global["se-ltn-elevator-clearance-name"].value,
}

function Delivery.on_runtime_mod_setting_changed(e)
	if e.setting == "se-ltn-use-elevator-clearance" then
		Delivery.use_clearance = settings.global["se-ltn-use-elevator-clearance"].value
	elseif e.setting == "se-ltn-elevator-clearance-name" then
		Delivery.clearance_name = settings.global["se-ltn-elevator-clearance-name"].value
	end
end

--- @param train LuaTrain
local function train_richtext(train)
	local loco = Train.get_main_locomotive(train)
	if loco and loco.valid then
		return string.format("[train=%d] %s", loco.unit_number, loco.backer_name)
	else
		return "[train=]"
	end
end

--- @param entity LuaEntity a carriage or a train-stop
--- @param schedule_records table array of TrainScheduleRecord (Factorio concept)
--- @param surface_connections LtnSurfaceConnection[]
local function add_closest_elevator_to_schedule(entity, schedule_records, surface_connections)
	local found_stop = nil
	local distance = 2147483647 -- maxint

	for _, connection in pairs(surface_connections) do
		-- which entity we use is not important, both map to the same ElevatorData structure
		-- but the entity might have become invalid between the LTN dispatcher's tick and this one
		if connection.entity1 and connection.entity1.valid then
			local elevator = Elevator.from_unit_number(connection.entity1.unit_number)
			if elevator then -- the connection might not belong to se-ltn-glue
				local stop = elevator.ground.stop
				if not (stop and stop.valid and stop.surface == entity.surface) then
					stop = elevator.orbit.stop
				end

				if stop and stop.valid and stop.surface == entity.surface then
					-- get_distance_squared avoids calculating a sqrt. That's unnecessary when comparing distances.
					local stop_distance = Misc.get_distance_squared(stop.position, entity.position)
					if (not found_stop) or (stop_distance < distance) then
						found_stop = stop
						distance = stop_distance
					end
				elseif debug_log then
					log(string.format("both elevator stops of connection [%s, %d] are either invalid or not on the same surface as the target",	connection.entity1.name, connection.entity1.unit_number))
				end
			elseif debug_log then log(string.format("no elevator data for connection [%s, %d]", connection.entity1.name, connection.entity1.unit_number)) end
		elseif debug_log then log("stale connection entity") end
	end

	if found_stop then
		-- No temp stops. This would require keeping the delivery data for use in on_train_teleport_started to know which elevators the delivery can use.
		-- This is further complicated when elevator surface connections are removed from LTN during the delivery,
		-- because the connection data is immediately removed in that case, making finding the corresponding elevator stops impossible.
		table.insert(schedule_records, {
			station = found_stop.backer_name
		})
		if Delivery.use_clearance then
			table.insert(schedule_records, {
				station = Delivery.clearance_name
			})
		end
	elseif debug_log then log("failed to find a suitable elevator stop to add to the schedule") end
end

--- @param delivery LtnDelivery
--- @param from_stop LuaEntity
--- @param to_stop LuaEntity
local function setup_cross_surface_schedule(delivery, from_stop, to_stop)
	local train = delivery.train
	local loco = Train.get_main_locomotive(train)
	if not loco or (loco.surface == from_stop.surface and loco.surface == to_stop.surface) then
		return -- train without a locomotive or intra-surface delivery
	end
	local surface_connections = delivery.surface_connections
	if message_level >= 3 then
		loco.force.print({"se-ltn-glue-message.cross-surface-delivery", train_richtext(train), #surface_connections})
	end

	local new_records = {}
	local passage_count = 0

	local from_index, to_index

	local stop_index, _, stop_type = remote.call("logistic-train-network", "get_next_logistic_stop", train)
	if stop_type == "provider" then
		from_index = stop_index
		stop_index, _, stop_type = remote.call("logistic-train-network", "get_next_logistic_stop", train, stop_index + 1)
	end
	if stop_type == "requester" then
		to_index = stop_index
	end

	if debug_log then log(string.format("preparing cross surface delivery for [train=%d], provider at #%s, requester at #%s", loco.unit_number, from_index, to_index)) end

	for old_index, record in pairs(train.schedule.records) do
		if old_index == from_index and loco.surface ~= from_stop.surface then
			-- (currently cannot happen, the train is always sourced from the provider surface)
			-- different surfaces implies no temp-stop before this record to consider
			add_closest_elevator_to_schedule(loco, new_records, surface_connections)
			passage_count = passage_count + 1
		end

		if old_index == to_index and from_stop.surface ~= to_stop.surface then
			-- different surfaces implies no temp-stop before this record to consider
			add_closest_elevator_to_schedule(from_stop, new_records, surface_connections)
			passage_count = passage_count + 1
		end

		table.insert(new_records, record)

		if old_index == to_index and passage_count == 1 then
			-- train is not yet on the surface it came from
			add_closest_elevator_to_schedule(to_stop, new_records, surface_connections)
			passage_count = passage_count + 1
		end
	end

	train.schedule = {
		current = train.schedule.current,
		records = new_records,
	}
end

-- the following events happen in the order their handler methods are declared

function Delivery.on_stops_updated(e)
	global.ltn_stops = e.logistic_train_stops or {}
end

function Delivery.on_dispatcher_updated(e)
	local deliveries = e.deliveries
	local ltn_stops = global.ltn_stops

	for _, train_id in pairs(e.new_deliveries) do
		local delivery = deliveries[train_id]
		if delivery and delivery.surface_connections and next(delivery.surface_connections) then
			local from_stop = ltn_stops[delivery.from_id]
			local to_stop = ltn_stops[delivery.to_id]

			if from_stop and from_stop.entity and from_stop.entity.valid
			and to_stop and from_stop.entity and to_stop.entity.valid
			and delivery.train and delivery.train.valid then
				setup_cross_surface_schedule(delivery, from_stop.entity, to_stop.entity)
			end
		end
	end
end

function Delivery.on_train_teleport_started(e)
	local train_has_delivery = remote.call("logistic-train-network", "reassign_delivery", e.old_train_id_1, e.train)
	if train_has_delivery then
		remote.call("logistic-train-network", "get_or_create_next_temp_stop", e.train)

		if message_level >= 3 then
			local first_carriage = e.train.carriages[1]
			-- If the locomotive is not the first carriage in driving direction
			-- the message will be missing the backer_name of the locomotive because the invisible elevator tug doesn't have one.
			first_carriage.force.print({ "se-ltn-glue-message.re-assign-delivery", train_richtext(e.train) })
		end
	end
end

return Delivery
