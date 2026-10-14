-----------------
---- STARTUP ----
-----------------

-- What Lucid Settings > Startup sets: environment variables, apps opened at
-- login, and whether the session starts the XDG autostart entries
-- (~/.config/autostart). Settings writes ~/.config/hypr/lucid-startup.lua and
-- runs LucidStartup.apply() after a change. modules/autostart.lua and
-- modules/env.lua are yours and are left alone; a reinstall rewrites those
-- two, but not the data file.

local M = {}

M.data = os.getenv("HOME") .. "/.config/hypr/lucid-startup.lua"
-- what this login started with, for Settings to tell a change that is already
-- in force from one that waits for the next login. one per Hyprland instance,
-- so a reload keeps the first one
M.session = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/lucid-startup-"
    .. (os.getenv("HYPRLAND_INSTANCE_SIGNATURE") or "none") .. ".json"

-- the session's own: setting one of these from Settings would cut apps off
-- from the display, the bus or the user's files
local PROTECTED = {
    WAYLAND_DISPLAY = true, DISPLAY = true, XDG_RUNTIME_DIR = true,
    HYPRLAND_INSTANCE_SIGNATURE = true, HYPRLAND_CMD = true, HOME = true,
    USER = true, LOGNAME = true, SHELL = true, DBUS_SESSION_BUS_ADDRESS = true,
    XDG_SESSION_ID = true, XDG_SESSION_TYPE = true, XDG_CURRENT_DESKTOP = true,
}

function M.valid_name(name)
    return type(name) == "string" and name:match("^[A-Za-z_][A-Za-z0-9_]*$") ~= nil
        and not PROTECTED[name]
end

-- the file is data only, so it runs with an empty environment
local function config()
    local chunk = loadfile(M.data, "t", {})
    local ok, cfg = false, nil
    if chunk then ok, cfg = pcall(chunk) end
    if not ok or type(cfg) ~= "table" then cfg = {} end
    if type(cfg.env) ~= "table" then cfg.env = {} end
    if type(cfg.apps) ~= "table" then cfg.apps = {} end
    return cfg
end

local function quote(s)
    return '"' .. tostring(s):gsub('[%c"\\]', function(c)
        return c == '"' and '\\"' or c == "\\" and "\\\\" or string.format("\\u%04x", c:byte())
    end) .. '"'
end

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- the variables to set, name -> value, in the order given
local function wanted(cfg)
    local out, order = {}, {}
    for _, e in ipairs(cfg.env) do
        if type(e) == "table" and M.valid_name(e.name) and type(e.value) == "string" then
            if out[e.name] == nil then order[#order + 1] = e.name end
            out[e.name] = e.value
        end
    end
    return out, order
end

-- set this session, names applied since login
local applied = {}

-- HYPRLAND_NO_SD_VARS asks Hyprland to leave systemd's environment alone,
-- and this module does the same
local to_systemd = os.getenv("HYPRLAND_NO_SD_VARS") == nil

-- variables reach what Hyprland starts from now on and, through the third
-- argument, systemd and D-Bus activated apps. one dropped here cannot be taken
-- out of Hyprland's own environment, only out of systemd's, so it is gone
-- for good at the next login
function M.apply()
    local env, order = wanted(config())
    for _, name in ipairs(order) do
        if pcall(hl.env, name, env[name], to_systemd) then applied[name] = true end
    end
    if not to_systemd then return end
    local gone = {}
    for name in pairs(applied) do
        if env[name] == nil then gone[#gone + 1] = shell_quote(name) end
    end
    if #gone > 0 then
        hl.exec_cmd("systemctl --user unset-environment " .. table.concat(gone, " "))
        for _, q in ipairs(gone) do applied[q:sub(2, -2)] = nil end
    end
end

local function write_session(cfg, env, order, xdg)
    local f = io.open(M.session, "r")
    if f then f:close(); return end
    local vars, apps = {}, {}
    for _, name in ipairs(order) do vars[#vars + 1] = quote(name) .. ": " .. quote(env[name]) end
    for _, app in ipairs(cfg.apps) do
        if type(app) == "table" and type(app.cmd) == "string" and app.cmd ~= "" then
            apps[#apps + 1] = quote(app.name or app.cmd)
        end
    end
    f = io.open(M.session, "w")
    if not f then return end
    f:write("{\"time\": " .. os.time()
        .. ", \"env\": {" .. table.concat(vars, ", ")
        .. "}, \"apps\": [" .. table.concat(apps, ", ")
        .. "], \"xdg\": " .. tostring(xdg) .. "}\n")
    f:close()
end

hl.on("hyprland.start", function()
    local cfg = config()
    local env, order = wanted(cfg)
    for _, app in ipairs(cfg.apps) do
        if type(app) == "table" and type(app.cmd) == "string" and app.cmd ~= "" then
            hl.exec_cmd(app.cmd)
        end
    end
    -- what a desktop session manager such as uwsm does: systemd turns each
    -- entry into a unit, honouring Hidden, OnlyShowIn and NotShowIn. when the
    -- session already started the target, starting it again does nothing
    -- the units need the display, so the session's variables go to systemd in
    -- the same command rather than racing Hyprland's own export of them
    local xdg = cfg.xdg == true
    if xdg then
        local start = "systemctl --user start xdg-desktop-autostart.target"
        if to_systemd then
            start = "systemctl --user import-environment DISPLAY WAYLAND_DISPLAY"
                .. " HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP; " .. start
        end
        hl.exec_cmd(start)
    end
    write_session(cfg, env, order, xdg)
end)

-- the settings page runs hyprctl eval 'LucidStartup.apply()' after a change
LucidStartup = M
pcall(M.apply)

return M
