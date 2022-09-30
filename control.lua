local flib = require("__flib__.train")
Get_Main_Locomotive = flib.get_main_locomotive
format = string.format

require("__LogisticTrainNetwork__.script.utils") -- Make_Train_RichText 

local function register_event_handlers()
	script.on_event(remote.call("space-exploration", "get_on_train_teleport_started_event"), function(event)
		local loco = Get_Main_Locomotive(event.train)

		local trainText = Make_Train_RichText(event.train, loco and loco.backer_name or "unknown")
		-- TODO should become a localized string
		local msg = "[SE-LTN-glue] New "..trainText.." arrived through an elevator, notifying LTN about possible delivery re-assignment"
		-- TODO this should honor LTN's setting for the reporting level. LTN printmsg() can't be used, though. Its message-throttling buffer isn't available outside of LTN.
		game.print(msg)

		remote.call("logistic-train-network", "reassign_delivery", event.old_train_id_1, event.train)
	end)

	script.on_event(remote.call("logistic-train-network", "on_delivery_created"), function(event)
		local new_records = {}

		for _, record in pairs(event.train.schedule.records) do
			table.insert(new_records, record)
			if record.station == event.from then
				-- totally hardcoded prototype code for now, the test map has the provider in orbit and the requester on the ground
				table.insert(new_records, {
					station = "[img=entity/se-space-elevator]  Nauvis ↓",
				})
			end
		end

		table.insert(new_records, {
			station = "[img=entity/se-space-elevator]  Nauvis ↑",
		})

		event.train.schedule = {
			current = event.train.schedule.current,
			records = new_records,
		}
	end)
end

script.on_init(register_event_handlers)
script.on_load(register_event_handlers)