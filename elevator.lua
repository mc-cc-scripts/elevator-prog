---@class scm
local scm = require("./scm")

---@class HelperFunctions
local helper = scm:load("helperFunctions")

---@class elevator
local elevator = {}

elevator.config = {
    protocol = "elevator",
    waitAtTarget = 2, -- wait 2 seconds at every target
    gearshiftSide = "left",
    sequencedGearshiftSide = "back",
    verbose = true,
    uiLibrary = "elevatorDefaultUI"
}
elevator.commands = {
    ["serve"] = {
        ---@param args table
        func = function (args)
            elevator:serve(elevator.config.protocol, args[2])
        end,
        requiresArgs = 2,
        help = "elevator serve <elevator_name>"
    },
    ["floor"] = {
        ---@param args table
        func = function (args)
            elevator:floor(elevator.config.protocol, args[2], args[3])
        end,
        requiresArgs = 3,
        help = "elevator floor <elevator_name> <floor_number>"
    }
}

elevator.ui = scm:load(elevator.config.uiLibrary)

--- Not really needed as extra functions
--- maybe get rid of them and just use textutils.serialise / unserialise
---@param obj table
---@return string
local function pack(obj)
    return textutils.serialise(obj)
end

---@param obj string
---@return table | nil
local function unpack(str)
    return textutils.unserialise(str)
end

---@param protocol string
---@param hostname string
function elevator:serve(protocol, hostname)
    rednet.host(protocol, hostname)
    print('Elevator started with protocol: ' .. protocol .. ' and hostname: ' .. hostname)
    print("Add floors with `elevator floor " .. hostname .. " <floor_number>`.")

    local queue = {}
    local currentPos = -1 -- has to be set by the first floor that connects to the monitor
    local moveDown = false
    local status = "idle"
    local lastIndex = 0
    self.floors = {}

    while true do
        local id, message, _ = rednet.receive(protocol)
        local obj = unpack(message)

        if (obj) then
            if obj.type == "register" or not self.floors[obj.floor] then
                self.floors[obj.floor] = id
            end

            if obj.type == "call" then
                if self.config.verbose then print("Received call to floor " .. obj.floor) end
                if currentPos ~= obj.floor then
                    lastIndex = lastIndex + 1
                    queue[obj.floor] = lastIndex
                    if self.config.verbose then print("Floor " .. obj.floor .. " added to queue.") end
                end
            elseif obj.type == "reached" then
                if self.config.verbose then print("Reached floor " .. obj.floor) end
                currentPos = obj.floor
                if (queue[currentPos]) then
                    queue[currentPos] = nil
                    if helper.tablelength(queue) == 0 then lastIndex = 0 end
                end

                status = "idle"
                if self.config.verbose then print("Status set to \"idle\".") end
            end

            -- broadcast floor info to all floors
            local obj = {
                type = "update_floors",
                floors = {}
            }
            local index = 1
            for floor, id in pairs(self.floors) do
                obj.floors[index] = {
                    number = floor,
                    isCurrent = currentPos == floor and true or false,
                    isQueued = queue[floor] and true or false
                }
                index = index + 1
            end
            rednet.broadcast(pack(obj), protocol)
        end

        if currentPos ~= -1 and status == "idle" then
            if helper.tablelength(queue) > 0 then
                local targetFloor = nil
                local minIndex = nil
                local floorQueue = ""
                for floor, index in pairs(queue) do
                    floorQueue = floorQueue .. floor .. " "
                    if targetFloor == nil or minIndex > index then
                        targetFloor = floor
                        minIndex = index
                    end

                    local sendObj = {
                        type = "sleep",
                        duration = self.config.waitAtTarget
                    }
                    if self.config.verbose then print ("Telling floor " .. floor .. " to wait " .. self.config.waitAtTarget .. " seconds.") end
                    rednet.send(self.floors[floor], pack(sendObj), protocol)
                end

                if self.config.verbose then print("Queue: " .. floorQueue) end
                if self.config.verbose then print("Next target: " .. targetFloor) end

                moveDown = currentPos > targetFloor

                status = "moving"
                if self.config.verbose then print("Status set to \"moving\".") end
                redstone.setOutput(self.config.gearshiftSide, moveDown)
                sleep(0.1)
                redstone.setOutput(self.config.sequencedGearshiftSide, true)
                sleep(0.4)
                redstone.setOutput(self.config.sequencedGearshiftSide, false)
            end
        end
    end
end


-- Floor functions
function elevator:floorReceive()
    while true do 
        local _, message, _ = rednet.receive(self.protocol)
        local obj = unpack(message)
        if obj and obj.type == "sleep" then
            self.wait = tonumber(obj.duration)
            if self.config.verbose then print("Received request to wait " .. self.wait .. " seconds.") end
        elseif obj and obj.type == "update_floors" then
            self.floors = obj.floors
            if self.monitor then self.ui.draw(self.ui, self.floors) end
        end
    end
end

function elevator:waitForMonitorConnect()
    while true do
        local monitor = peripheral.find("monitor")
        if monitor then
            if not self.monitor then
                self.monitor = monitor

                self.monitor.setCursorPos(1, 1)
                self.monitor.write("Floor:")
                self.monitor.write(self.floor)

                self.ui.draw(self.ui, self.floors)

                local obj = {
                    type = "reached",
                    floor = self.floor
                }

                if self.wait > 0 then
                    if self.config.verbose then print("Waiting " .. self.wait .. " seconds.") end
                    sleep(self.wait)
                    self.wait = 0
                end

                if self.config.verbose then print ("Sending \"reached\" to server.") end
                rednet.send(self.server_id, pack(obj), self.protocol)
            end
        else
            self.monitor = nil
        end
        sleep(0.5)
    end
end

function elevator:waitForMonitorInput()
    while true do
        local _, side, x, y = os.pullEvent("monitor_touch")
        local floor_clicked = self.ui:click(side, x, y)
        if floor_clicked then
            if self.config.verbose then print ("Floor clicked: " .. floor_clicked) end
            local obj = {
                type = "call",
                floor = floor_clicked
            }
            
            if self.config.verbose then print("Sending \"call\" for floor " .. floor_clicked .. " to server.") end
            rednet.send(self.server_id, pack(obj), self.protocol)

            if self.monitor then self.ui.draw(self.ui, self.floors) end
        end
    end
end

function elevator:waitForInput()
    while true do
        if self.monitor then
            if self.config.verbose then print("Floor: " .. self.floor) end
            if self.config.verbose then print("Target floor: ") end
            local targetFloor = read()
            if self.config.verbose then print("targetFloor: " .. targetFloor) end
            local obj = {
                type = "call",
                floor = targetFloor
            }
            
            if self.config.verbose then print("Sending \"call\" for floor " .. targetFloor .. " to server.") end
            rednet.send(self.server_id, pack(obj), self.protocol)
        end

        sleep(0.5)
    end
end

function elevator:waitForRedstoneSignal()
    local sides = {"front", "back", "left", "right", "top", "bottom"}
    while true do
        local hasInput = false 
        for i = 1, #sides do
            if redstone.getInput(sides[i]) then
                hasInput = true
                break
            end
        end

        if hasInput then
            local obj = {
                type = "call",
                floor = self.floor
            }

            if self.config.verbose then print ("Received redstone input. Sending \"call\" for floor " .. self.floor .. " to server.") end
            rednet.send(self.server_id, pack(obj), self.protocol)
        end
        sleep(0.5)
    end
end

---@param protocol string
---@param hostname string
---@param floor_number string
function elevator:floor(protocol, hostname, floor_number)
    self.floor = floor_number
    self.floors = {}
    self.server_id = rednet.lookup(protocol, hostname)
    self.protocol = protocol
    self.hostname = hostname
    self.wait = 0
    if not self.server_id then
        print("Error: Could not connect to elevator server with hostname: " .. self.hostname .. " and protocol: " .. self.protocol)
        return
    end
    
    print('Floor ' .. self.floor .. ' reporting to elevator with protocol: ' .. self.protocol .. ' and hostname: ' .. self.hostname)
    rednet.send(self.server_id, pack({type="register", floor=self.floor}), self.protocol)

    parallel.waitForAny(
        function ()
            elevator:waitForMonitorConnect()
        end,
        function ()
            elevator:waitForInput()            
        end,
        function ()
            elevator:waitForMonitorInput()            
        end,
        function ()
            elevator:waitForRedstoneSignal()
        end,
        function ()
            elevator:floorReceive()
        end
    )
end

---@param args table
function elevator:run(args)
    local command = args[1]
    if self.commands[command] then
        if not args[self.commands[command].requiresArgs] then
            print("Missing arguments.")
            print(self.commands[command].help)
            return
        end

        peripheral.find("modem", rednet.open)

        if not rednet.isOpen() then
            error("Could not open modem.")
            return
        end

        self.commands[command].func(args)

        rednet.close()
    elseif command then
        print("Command not found: " .. command)
    else
        print("Missing command.")
        print("Available commands:")
        for k, v in pairs(self.commands) do
            print(k)
            print("\t" .. v.help)
        end
    end
end

local args = {...}
elevator:run(args)

return elevator