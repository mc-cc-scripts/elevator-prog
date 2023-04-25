local elevator = {}

elevator.config = {
    protocol = "elevator",
    modemSlot = pocket and "back" or "right"
}
elevator.commands = {
    ["serve"] = {
        func = function (args)
            elevator:serve(elevator.config.protocol, args[2])
        end
    },
    ["floor"] = {
        func = function (args)
        end
    }
}

function elevator:serve(protocol, hostname)
    rednet.host(protocol, hostname)
    print('Serving elevator with protocol: ' .. protocol .. ' and hostname: ' .. hostname .. '...')

    while true do
        local deviceID, message, _ = rednet.receive(protocol)

        -- handle stuff
        -- floor computers should tell the server on which floor the elevator is
        -- floor computers can send requests to call the elevator (button press on computer)
        -- via the monitor on the moving platform, a player can send a request to move to a specific floor
    end
end

function elevator:run(args)
    local command = args[1]
    if self.commands[command] then
        rednet.open(self.config.modemSlot)
        
        if not rednet.isOpen(self.config.modemSlot) then
            error("Could not open modem '".. self.config.modemSlot .. "'")
            return
        end

        self.commands[command].func(args)

        rednet.close(self.config.modemSlot)
    else
        print("Command not found: " .. command)
    end
end

local args = {...}
if not args[2] then
    print("Missing arguments.")
    return
else
    elevator:run(args)
end

return elevator