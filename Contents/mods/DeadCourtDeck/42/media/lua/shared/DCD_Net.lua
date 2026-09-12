----------
--ESTRAL--
----------

require "DCD_Core"

DCD = DCD or {}
DCD_Net = DCD_Net or {}

-- looked up at call time: shared/ loads before client/ and server/, so neither dispatcher
-- exists yet when this file runs.
local function DCD_serverHandler(command)
    return DCD_Commands and DCD_Commands.handlers and DCD_Commands.handlers[command]
end

local function DCD_clientHandler()
    return DCD_ClientState and DCD_ClientState.onCommand
end

-- with no remote server the send is a direct call into the handler that would have
-- received it, so singleplayer runs the same open and trade code the server does.
function DCD_Net.toServer(player, command, args)
    player = player or getPlayer()
    args = args or {}

    if DCD.hasRemoteServer() then
        sendClientCommand(player, DCD.MODULE, command, args)
        return
    end

    local handler = DCD_serverHandler(command)
    if not handler then
        DCD.warn("no server handler for " .. tostring(command))
        return
    end

    local ok, err = pcall(handler, player, args)
    if not ok then DCD.warn("server handler " .. tostring(command) .. " failed: " .. tostring(err)) end
end

function DCD_Net.toClient(player, command, args)
    args = args or {}

    if isServer() then
        sendServerCommand(player, DCD.MODULE, command, args)
        return
    end

    local handler = DCD_clientHandler()
    if not handler then return end

    -- splitscreen: the handler needs to know which of the local players this was for.
    args.playerNum = player and player:getPlayerNum() or 0

    local ok, err = pcall(handler, DCD.MODULE, command, args)
    if not ok then DCD.warn("client handler " .. tostring(command) .. " failed: " .. tostring(err)) end
end
