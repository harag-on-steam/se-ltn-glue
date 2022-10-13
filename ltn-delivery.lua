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

--- @param train LuaEntity
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
--- @param surface_connections { entity1 : LuaEntity, entity2 : LuaEntity, network_id : integer }[]
local function add_closest_elevator_to_schedule(entity, schedule_records, surface_connections)
	local found_stop = nil
	local distance = 2147483647 -- maxint

	for _, connection in pairs(surface_connections) do
		-- which entity we use is not important, both map to the same ElevatorData structure
		local elevator = Elevator.from_unit_number(connection.entity1.unit_number)
		if elevator then -- the connection might not belong to se-ltn-glue
			local stop = elevator.ground.stop
			if not (stop and stop.valid and stop.surface == entity.surface) then
				stop = elevator.orbit.stop
			end

			if stop and stop.valid and stop.surface == entity.surface then
				local stop_distance = Misc.get_distance_squared(stop.position, entity.position)
				if (not found_stop) or (stop_distance < distance) then
					found_stop = stop
					distance = stop_distance
				end
			end
		end
	end

	if found_stop then
		-- no temp stops, entities to find the appropriate rail segments are only available in this event
		-- but not when the train arrives on the corresponding surface
		-- just inform the player that elevators with different network_ids need different names. TODO FAQ? InformaTron?
		table.insert(schedule_records, {
			station = found_stop.backer_name
		})
		if Delivery.use_clearance then
			table.insert(schedule_records, {
				station = Delivery.clearance_name
			})
		end
	end
end

--- @param train LuaTrain
--- @param from_stop LuaEntity
--- @param to_stop LuaEntity
--- @param surface_connections { entity1 : LuaEntity, entity2 : LuaEntity, network_id : integer }[]
local function setup_cross_surface_schedule(train, from_stop, to_stop, surface_connections)
	local loco = Train.get_main_locomotive(train)
	if not loco or (loco.surface == from_stop.surface and loco.surface == to_stop.surface) then
		return -- train without a locomotive or intra-surface delivery
	end

	log("preparing cross surface delivery for [train="..loco.unit_number.."]")

	local new_records = {}
	local passage_count = 0

	for _, record in pairs(train.schedule.records) do
		if record.station == from_stop.backer_name and loco.surface ~= from_stop.surface then
			-- (currently cannot happen, the train is always sourced from the provider surface)
			-- different surfaces implies no temp-stop before this record to consider
			add_closest_elevator_to_schedule(loco, new_records, surface_connections)
			passage_count = passage_count + 1
		end

		if record.station == to_stop.backer_name and from_stop.surface ~= to_stop.surface then
			-- different surfaces implies no temp-stop before this record to consider
			add_closest_elevator_to_schedule(from_stop, new_records, surface_connections)
			passage_count = passage_count + 1
		end

		table.insert(new_records, record)

		if record.station == to_stop.backer_name and passage_count < 2 then
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
				setup_cross_surface_schedule(delivery.train, from_stop.entity, to_stop.entity, delivery.surface_connections)
			end
		end

		global.pending_new_deliveries[train_id] = nil
	end
end

function Delivery.on_train_teleport_started(e)
	local train_has_delivery = remote.call("logistic-train-network", "reassign_delivery", e.old_train_id_1, e.train)
	if message_level >= 3 and train_has_delivery then
		local first_carriage = e.train.carriages[1]
		-- If the locomotive is not the first carriage in driving direction
		-- the message will be missing the backer_name of the locomotive because the invisible elevator tug doesn't have one.
		first_carriage.force.print({ "se-ltn-glue-message.re-assign-delivery", train_richtext(e.train) })
	end
end

return Delivery
