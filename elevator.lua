local elevator = {}
elevator.commands = {
    ["serve"] = {
        func = function ()
        end
    },
    ["floor"] = {
        func = function ()
        end
    }
}
function elevator:run(command)
    if self.commands[command] then
        self.commands[command].func()
    end
end

local args = {...}
if not args[1] then
    print("Missing arguments.")
    return
else
    for i = 1, #elevator.commands do
        if args[1] == elevator.commands[i] then
            elevator:run(elevator.commands[i])
            return
        end
    end

    print("Command not found: " .. args[1])
end

return elevator