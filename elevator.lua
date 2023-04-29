local elevator = {}

elevator.config = {
    protocol = "elevator",
    waitAtTarget = 2, -- wait 2 seconds at every target
    gearshiftSide = "left",
    sequencedGearshiftSide = "back"
}
elevator.commands = {
    ["serve"] = {
        func = function (args)
            elevator:serve(elevator.config.protocol, args[2])
        end,
        requiresArgs = 2,
        help = "elevator serve <elevator_name>"
    },
    ["floor"] = {
        func = function (args)
            elevator:floor(elevator.config.protocol, args[2], args[3])
        end,
        requiresArgs = 3,
        help = "elevator floor <elevator_name> <floor_number>"
    }
}

local function pack(obj)
    return textutils.serialise(obj)
end

local function unpack(str)
    return textutils.unserialise(str)
end

-- @TODO: should load from scm
local function tablelength(T)
    local count = 0
    for _ in pairs(T) do count = count + 1 end
    return count
end

function elevator:serve(protocol, hostname)
    rednet.host(protocol, hostname)
    print('Serving elevator with protocol: ' .. protocol .. ' and hostname: ' .. hostname)

    local queue = {}
    local currentPos = -1 -- has to be set by the first floor that connects to the monitor
    local moveDown = false
    local status = "idle"
    local lastIndex = 0

    while true do
        print("loop")
        local _, message, _ = rednet.receive(protocol)
        print(message)
        local obj = unpack(message)

        if (obj) then
            print("yep")
            if obj.type == "call" then
                print(currentPos, obj.floor)
                if currentPos ~= obj.floor then
                    lastIndex = lastIndex + 1
                    queue[obj.floor] = lastIndex
                end
            elseif obj.type == "reached" then
                currentPos = obj.floor
                if (queue[currentPos]) then
                    queue[currentPos] = nil
                    if tablelength(queue) == 0 then lastIndex = 0 end
                    sleep(self.config.waitAtTarget)
                end

                status = "idle"
            end
        end

        if currentPos ~= -1 and status == "idle" then
            print ("queue length", tablelength(queue))
            if tablelength(queue) > 0 then
                local targetFloor = nil
                local minIndex = nil
                for floor, index in pairs(queue) do
                    print("for pairs", floor, index, targetFloor)
                    if targetFloor == nil or minIndex > index then
                        targetFloor = floor
                        minIndex = index
                    end
                end

                moveDown = currentPos > targetFloor

                status = "moving"
                redstone.setOutput(self.config.gearshiftSide, moveDown)
                sleep(0.1)
                redstone.setOutput(self.config.sequencedGearshiftSide, true)
                sleep(0.4)
                redstone.setOutput(self.config.sequencedGearshiftSide, false)
            end
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

                local obj = {
                    type = "reached",
                    floor = self.floor
                }

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
        if self.monitor then
            print("Floor: " .. self.floor)
            print("Target floor: ")
            local targetFloor = read()
            print("targetFloor: " .. targetFloor)
            local obj = {
                type = "call",
                floor = targetFloor
            }
            
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

            rednet.send(self.server_id, pack(obj), self.protocol)
        end
        sleep(0.5)
    end
end

function elevator:floor(protocol, hostname, floor_number)
    self.floor = floor_number
    self.server_id = rednet.lookup(protocol, hostname)
    self.protocol = protocol
    self.hostname = hostname
    if not self.server_id then
        print("Error: Could not connect to elevator server with hostname: " .. self.hostname .. " and protocol: " .. self.protocol)
        return
    end
    
    print('Floor ' .. self.floor .. ' reporting to elevator with protocol: ' .. self.protocol .. ' and hostname: ' .. self.hostname)

    parallel.waitForAny(
        function ()
            elevator:waitForMonitorConnect()
        end,
        function ()
            elevator:waitForMonitorInput()            
        end,
        function ()
            elevator:waitForRedstoneSignal()
        end
    )
end

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