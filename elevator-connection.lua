--- @class ElevatorEndData
--- @field connector LuaEntity
--- @field elevator LuaEntity
--- @field stop LuaEntity
--- @field connector_id integer
--- @field elevator_id integer
--- @field opposite_id integer

--- @class ElevatorData
--- @field ground ElevatorEndData
--- @field orbit ElevatorEndData
--- @field ltn_enabled boolean
--- @field network_id integer

local Elevator = {
    name_elevator = "se-space-elevator",
    name_stop = "se-space-elevator-train-stop",
    name_connector = "se-ltn-elevator-connector",
}

local ENTITY_SEARCH = { Elevator.name_elevator, Elevator.name_stop, Elevator.name_connector }

--- Creates a new ElevatorEndData structure if all necessary entities are present on the given surfaces at the given location
--- @param surface LuaSurface 
--- @param position { x: number, y: number } supposed to be at the center of an elevator, will be searched in a 12-tile radius
--- @return ElevatorEndData|nil
local function search_entities(surface, position)
	local search_area = Area.expand(Area.from_position(position), 12) -- elevator is 24x24
    local elevator, stop, connector

	for _, found_entity in pairs(surface.find_entities_filtered {
		name = ENTITY_SEARCH,
		area = search_area,
	}) do
		if found_entity.name == Elevator.name_stop then
			stop = found_entity
		elseif found_entity.name == Elevator.name_elevator then
			elevator = found_entity
		elseif found_entity.name == Elevator.name_connector then
			connector = found_entity
		end
	end

    if not (elevator and elevator.valid and stop and stop.valid) then
        return nil
    end

    return {
        elevator = elevator,
        stop = stop,
        connector = connector,

        -- these are kept in the record for table cleanup in case the entities become unreadable
        elevator_id = elevator.unit_number,
        connector_id = connector and connector.valid and connector.unit_number,
    }
end

--- Creates a surface connector entity within the given elevator data and adds a lookup from its unit_number to the main elevator data
--- @param data ElevatorData
--- @param ground_or_orbit ElevatorEndData the subtable in data that should be modified
local function create_connector(data, ground_or_orbit)
    local elevator = ground_or_orbit.elevator
    game.print(string.format("creating connector [gps=%s,%s,%s]", elevator.position.x, elevator.position.y, elevator.surface.name))

    local connector = elevator.surface.create_entity {
        name = Elevator.name_connector,
        position = elevator.position,
        force = elevator.force,
        create_build_effect_smoke = false,
    }
    connector.destructible = false
    connector.operable = false

    ground_or_orbit.connector = connector
    ground_or_orbit.connector_id = connector.unit_number

    global.elevators[ground_or_orbit.connector_id] = data
end

--- Disconnects elevators from LTN by destroying the corresponding surface connectors
--- @param data ElevatorData
local function disconnect(data)
    if data.ground.connector_id then
        global.elevators[data.ground.connector_id] = nil
        data.ground.connector_id = nil
    end
    if data.orbit.connector_id then
        global.elevators[data.orbit.connector_id] = nil
        data.orbit.connector_id = nil
    end

    -- entity.destroy() also disconnects LTN
    if data.ground.connector and data.ground.connector.valid then
        game.print(string.format("destroying LTN connector for elevator [gps=%s,%s,%s]", data.ground.connector.position.x, data.ground.connector.position.y, data.ground.connector.surface.name))
        data.ground.connector.destroy()
    end
    if data.orbit.connector and data.orbit.connector.valid then
        game.print(string.format("destroying LTN connector for elevator [gps=%s,%s,%s]", data.orbit.connector.position.x, data.orbit.connector.position.y, data.orbit.connector.surface.name))
        data.orbit.connector.destroy()
    end
end

--- Register with Factorio to destroy LTN surface connectors when the corresponding elevator is removed
function Elevator.on_entity_destroyed(e)
    if not e.unit_number then return end

    local data = global.elevators[e.unit_number]
    if data then
        disconnect(data)

        global.elevators[data.ground.elevator_id] = nil
        global.elevators[data.orbit.elevator_id] = nil
    end
end

--- Either the surface.index and zone.type of the opposite surface or nil
--- @return integer|nil,string|nil
local function find_opposite_surface(surface_index)
    local zone = remote.call("space-exploration", "get_zone_from_surface_index", {surface_index = surface_index})
    if zone then
        local opposite_zone_index = (zone.type == "planet" and zone.orbit_index) or (zone.type == "orbit" and zone.parent_index) or nil
        if opposite_zone_index then
            local opposite_zone = remote.call("space-exploration", "get_zone_from_zone_index", {zone_index = opposite_zone_index})
            if opposite_zone and opposite_zone.surface_index then -- a zone might not have a surface, yet
                return opposite_zone.surface_index, opposite_zone.type
            end
        end
    end
    return nil
end

--- Looks up the elevator data for the given unit_number. The data structure won't be created if it doesn't exist
--- @param unit_number integer the unit_number of a `se-space-elevator` or `se-ltn-elevator-connector`
--- @return ElevatorData|nil
function Elevator.from_unit_number(unit_number)
    local elevator = global.elevators[unit_number]
    return elevator or nil
end

--- Looks up the elevator data for the given entity. Creates the data structure if it doesn't exist, yet.
--- @param entity? LuaEntity must be a `se-space-elevator` or `se-ltn-elevator-connector`
--- @return ElevatorData|nil
function Elevator.from_entity(entity)
    if not (entity and entity.valid) then 
        return nil
    end
    local data = Elevator.from_unit_number(entity.unit_number)
    if data then return data end

    -- construct new data
    if entity.name ~= Elevator.name_elevator and entity.name ~= Elevator.name_connector then
        error("entity must be an elevator or the corresponding connector entity")
    end

    local opposite_surface_index, opposite_zone_type = find_opposite_surface(entity.surface.index)
    if not opposite_surface_index then return nil end

    local end1 = search_entities(entity.surface, entity.position)
    if not end1 then return nil end

    local end2 = search_entities(game.surfaces[opposite_surface_index], entity.position)
    if not end2 then return nil end

    data = {
        ground = opposite_zone_type == "planet" and end2 or end1,
        orbit = opposite_zone_type == "orbit" and end2 or end1,
        ltn_enabled = end1.connector_id and end2.connector_id and true,
        network_id = -1, -- no entity in the world has this information so reset to -1
    }
    if data.ground == data.orbit then
        error("only know how to handle elevators in zone.type 'planet' and 'orbit'")
    end

    global.elevators[data.ground.elevator_id] = data
    global.elevators[data.orbit.elevator_id] = data

    -- no need to track by registration number, both entities are valid and must have a unit_number
    Event.register_on_entity_destroyed(data.ground.elevator)
    Event.register_on_entity_destroyed(data.orbit.elevator)

    if data.ground.connector_id then
        global.elevators[data.ground.connector_id] = data
    end
    if data.orbit.connector_id then
        global.elevators[data.orbit.connector_id] = data
    end

    return data
end

--- Connects or disconnects the elevator from LTN based on ltn_enabled and updates the network_id when connected to LTN
--- @param data ElevatorData
function Elevator.update_connection(data)
    if data.ltn_enabled then
        if not (data.ground.connector and data.ground.connector.valid) then
            create_connector(data, data.ground)
        end
        if not (data.orbit.connector and data.orbit.connector.valid) then
            create_connector(data, data.orbit)
        end
        remote.call("logistic-train-network", "connect_surfaces", data.ground.connector, data.orbit.connector, data.network_id)
    else
        disconnect(data)
    end
end

return Elevator