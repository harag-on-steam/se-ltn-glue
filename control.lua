local flib_train = require("__flib__.train")
local flib_misc = require("__flib__.misc")

local get_main_locomotive = flib_train.get_main_locomotive
local get_distance_squared = flib_misc.get_distance_squared

format = string.format -- Make_Train_RichText uses this as a global
require("__LogisticTrainNetwork__.script.utils") -- Make_Train_RichText is defined as a global

local function add_closest_elevator_to_schedule(entity, schedule_records)
	local found_stop = nil
	local distance = 2147483647 -- maxint

	-- TODO could be optimized with a lookup per surface but there aren't that many per surface
	for _, elevator_stop in pairs(entity.surface.find_entities_filtered { name = "se-space-elevator-train-stop" }) do
		if (not found_stop) or (get_distance_squared(elevator_stop.position, entity.position) < distance) then
			found_stop = elevator_stop
		end
	end

	if found_stop then
		table.insert(schedule_records, {
			station = found_stop.backer_name
		})
	end

	-- TODO report missing elevator
end

local function register_event_handlers()
	script.on_event(remote.call("space-exploration", "get_on_train_teleport_started_event"), function(event)
		local loco = get_main_locomotive(event.train)

		local trainText = Make_Train_RichText(event.train, loco and loco.backer_name or "unknown")
		-- TODO should become a localized string
		local msg = "[SE-LTN-glue] New "..trainText.." arrived through an elevator, notifying LTN about possible delivery re-assignment"
		-- TODO this should honor LTN's setting for the reporting level. LTN printmsg() can't be used, though. Its message-throttling buffer isn't available outside of LTN.
		game.print(msg)

		remote.call("logistic-train-network", "reassign_delivery", event.old_train_id_1, event.train)
	end)

	script.on_event(remote.call("logistic-train-network", "on_delivery_created"), function(event)
		local new_records = {}

		local loco = get_main_locomotive(event.train)
		if not loco then
			return -- a train without a locomotive won't go anywhere
		end

		-- TODO these fields might not make it into on_delivery_created
		local from_stop = event.from_stop
		local to_stop = event.to_stop

		if loco.surface == from_stop.surface and loco.surface == to_stop.surface then
			return -- normal intra surface delivery, do nothing
		end

		local passage_count = 0

		for _, record in pairs(event.train.schedule.records) do
			if record.station == event.from and loco.surface ~= from_stop.surface then
				-- different surfaces implies no temp-stop before this record to consider
				add_closest_elevator_to_schedule(loco, new_records)
				passage_count = passage_count + 1
			end

			if record.station == event.to and from_stop.surface ~= to_stop.surface then
				-- different surfaces implies no temp-stop before this record to consider
				add_closest_elevator_to_schedule(from_stop, new_records)
				passage_count = passage_count + 1
			end

			table.insert(new_records, record)

			if record.station == event.to and passage_count < 2 then
				-- train is not yet on the surface it came from
				add_closest_elevator_to_schedule(to_stop, new_records)
				passage_count = passage_count + 1
			end
		end

		event.train.schedule = {
			current = event.train.schedule.current,
			records = new_records,
		}
	end)
end

script.on_init(register_event_handlers)
script.on_load(register_event_handlers)