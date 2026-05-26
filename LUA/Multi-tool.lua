-- crazy-streamer-tool.lua
-- OBS Studio single-file "crazy" Swiss-army streamer tool
-- Pure Lua, cross-platform, plugin-optional, and defensive by default.
-- By: Villain, 2026-05-25
obs = obslua
math.randomseed(os.time())

--------------------------------------------------------------------------------
-- Metadata / constants
--------------------------------------------------------------------------------

local SCRIPT_TAG = "[CST]"
local SCRIPT_VER = "1.0.0"

local FILTER_AUTO = "CST Auto Color"
local FILTER_TINT = "CST Silhouette Tint"
local FILTER_GLOW_A = "CST Glow A"
local FILTER_GLOW_B = "CST Glow B"
local FILTER_STROBE = "CST Strobe"

local BG_FILTER_CANDIDATES = {
	"background_removal",
	"background_remove_filter",
	"obs_backgroundremoval_filter"
}

local LOG_LEVELS = {
	INFO = "INFO",
	WARN = "WARN",
	ERROR = "ERROR",
	MAGIC = "MAGIC",
	HEALTH = "HEALTH"
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local settings_ref = nil

local st = {
	webcam_source = "",
	audio_source = "",
	media_source = "",
	chat_overlay_source = "",
	motion_source = "",

	talking_scene = "",
	waiting_scene = "",
	motion_scene = "",

	silhouette_preset = "Electric Purple",
	custom_color = 0xFFFF00FF, -- ARGB
	opacity = 85,
	glow_enable = true,
	outline_enable = true,
	reactive_enable = true,
	random_burst_enable = false,
	strobe_enable = false,

	cycle_enable = false,
	cycle_seconds = 8,

	bg_remove_enable = false,
	bg_threshold_preset = "Balanced",

	auto_scene_enable = false,
	silence_seconds = 4,
	voice_threshold_db = -34,
	motion_enable = false,

	nl_command = "",
	selected_preset_name = "Just Chatting",

	diagnostics_enable = true
}

local runtime = {
	color_index = 1,
	last_cycle_ts = 0,
	last_burst_ts = 0,
	last_strobe_ts = 0,
	strobe_state = false,

	last_voice_ts = 0,
	last_motion_ts = 0,
	last_diag_ts = 0,

	audio_db = -60.0,
	audio_norm = 0.0,

	bg_filter_id = nil,

	meter = nil,
	meter_attached_source = "",
	audio_meter_supported = false,

	pulse_phase = 0.0
}

local hotkeys = {
	cycle = { id = obs.OBS_INVALID_HOTKEY_ID, key = "hk_cycle_color" },
	random = { id = obs.OBS_INVALID_HOTKEY_ID, key = "hk_random_crazy" },
	bg_toggle = { id = obs.OBS_INVALID_HOTKEY_ID, key = "hk_toggle_bg" },
	chat_toggle = { id = obs.OBS_INVALID_HOTKEY_ID, key = "hk_toggle_chat" },
	media_pp = { id = obs.OBS_INVALID_HOTKEY_ID, key = "hk_media_pp" },
	media_next = { id = obs.OBS_INVALID_HOTKEY_ID, key = "hk_media_next" },
	health = { id = obs.OBS_INVALID_HOTKEY_ID, key = "hk_health" },
	magic = { id = obs.OBS_INVALID_HOTKEY_ID, key = "hk_apply_magic" }
}

-- Built-in 24 vibrant presets
local COLOR_PRESETS = {
	{ name = "Electric Purple", color = 0xFFFF00FF },
	{ name = "Neon Green", color = 0xFF39FF14 },
	{ name = "Cyber Blue", color = 0xFF00BFFF },
	{ name = "Hot Pink", color = 0xFFFF1493 },
	{ name = "Lava Orange", color = 0xFFFF5A1F },
	{ name = "Laser Red", color = 0xFFFF0033 },
	{ name = "Acid Yellow", color = 0xFFFFFF00 },
	{ name = "Mint Blast", color = 0xFF00FFC8 },
	{ name = "Volt Cyan", color = 0xFF00FFFF },
	{ name = "Royal Violet", color = 0xFF8A2BE2 },
	{ name = "Plasma Gold", color = 0xFFFFD700 },
	{ name = "Crimson Glow", color = 0xFFDC143C },
	{ name = "Aqua Storm", color = 0xFF00CED1 },
	{ name = "Sunset Peach", color = 0xFFFF8C69 },
	{ name = "Arctic Blue", color = 0xFF87CEFA },
	{ name = "Poison Lime", color = 0xFFBFFF00 },
	{ name = "Ultra Magenta", color = 0xFFFF00AA },
	{ name = "Infra Orange", color = 0xFFFF7F11 },
	{ name = "Galaxy Indigo", color = 0xFF4B0082 },
	{ name = "Pulse Teal", color = 0xFF00C9A7 },
	{ name = "Storm Gray", color = 0xFF8F8F8F },
	{ name = "Ghost White", color = 0xFFF8F8FF },
	{ name = "Matrix Green", color = 0xFF00FF66 },
	{ name = "Ice Violet", color = 0xFFB19CD9 }
}

-- User-named presets (saved in script settings)
local NAMED_PRESETS = {
	["Just Chatting"] = {
		color = 0xFFFF00FF, opacity = 82, glow = true, outline = true,
		reactive = true, random_burst = false, strobe = false,
		cycle = false, cycle_seconds = 8, bg_remove = true
	},
	["Gaming"] = {
		color = 0xFF39FF14, opacity = 90, glow = true, outline = true,
		reactive = true, random_burst = true, strobe = false,
		cycle = true, cycle_seconds = 8, bg_remove = true
	},
	["High Energy"] = {
		color = 0xFFFF0033, opacity = 95, glow = true, outline = true,
		reactive = true, random_burst = true, strobe = true,
		cycle = true, cycle_seconds = 5, bg_remove = true
	},
	["Chill"] = {
		color = 0xFF00BFFF, opacity = 72, glow = true, outline = false,
		reactive = true, random_burst = false, strobe = false,
		cycle = false, cycle_seconds = 10, bg_remove = true
	}
}

--------------------------------------------------------------------------------
-- Utility helpers
--------------------------------------------------------------------------------

local function now_s()
	return os.clock()
end

local function clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

local function contains(hay, needle)
	return string.find(hay, needle, 1, true) ~= nil
end

local function lower(s)
	if s == nil then return "" end
	return string.lower(s)
end

local function log(level, msg)
	local prefix = string.format("%s[%s] ", SCRIPT_TAG, level)
	obs.script_log(obs.LOG_INFO, prefix .. msg)
end

local function logi(msg) log(LOG_LEVELS.INFO, msg) end
local function logw(msg) log(LOG_LEVELS.WARN, msg) end
local function loge(msg) log(LOG_LEVELS.ERROR, msg) end
local function logm(msg) log(LOG_LEVELS.MAGIC, msg) end
local function logh(msg) log(LOG_LEVELS.HEALTH, msg) end

local function with_source(name, fn)
	if name == nil or name == "" then return nil end
	local src = obs.obs_get_source_by_name(name)
	if src == nil then return nil end
	local ok, ret = pcall(fn, src)
	obs.obs_source_release(src)
	if not ok then
		loge("Source operation failed for '" .. name .. "': " .. tostring(ret))
		return nil
	end
	return ret
end

local function create_data_from_table(tbl)
	local data = obs.obs_data_create()
	for k, v in pairs(tbl) do
		if type(v) == "boolean" then
			obs.obs_data_set_bool(data, k, v)
		elseif type(v) == "number" then
			if math.floor(v) == v then
				obs.obs_data_set_int(data, k, v)
			else
				obs.obs_data_set_double(data, k, v)
			end
		elseif type(v) == "string" then
			obs.obs_data_set_string(data, k, v)
		end
	end
	return data
end

local function bit_band(a, b)
	if bit and bit.band then
		return bit.band(a, b)
	end
	-- Fallback for environments lacking bit library
	local res, bitval = 0, 1
	while a > 0 and b > 0 do
		local ra, rb = a % 2, b % 2
		if ra == 1 and rb == 1 then res = res + bitval end
		a = math.floor(a / 2)
		b = math.floor(b / 2)
		bitval = bitval * 2
	end
	return res
end

local function color_to_channels(c)
	local a = math.floor(c / 0x1000000) % 0x100
	local r = math.floor(c / 0x10000) % 0x100
	local g = math.floor(c / 0x100) % 0x100
	local b = c % 0x100
	return a, r, g, b
end

local function channels_to_color(a, r, g, b)
	return (a * 0x1000000) + (r * 0x10000) + (g * 0x100) + b
end

local function lerp_color(c1, c2, t)
	local a1, r1, g1, b1 = color_to_channels(c1)
	local a2, r2, g2, b2 = color_to_channels(c2)
	local function l(x, y) return math.floor(x + (y - x) * t + 0.5) end
	return channels_to_color(l(a1, a2), l(r1, r2), l(g1, g2), l(b1, b2))
end

local function preset_color_by_name(name)
	for _, p in ipairs(COLOR_PRESETS) do
		if p.name == name then return p.color end
	end
	return st.custom_color
end

local function next_preset_index(current_idx)
	local n = #COLOR_PRESETS
	if n <= 0 then return 1 end
	local idx = current_idx + 1
	if idx > n then idx = 1 end
	return idx
end

--------------------------------------------------------------------------------
-- Source and scene enumeration
--------------------------------------------------------------------------------

local function source_has_video_flags(src)
	local flags = obs.obs_source_get_output_flags(src)
	return bit_band(flags, obs.OBS_SOURCE_VIDEO) ~= 0
end

local function source_has_audio_flags(src)
	local flags = obs.obs_source_get_output_flags(src)
	return bit_band(flags, obs.OBS_SOURCE_AUDIO) ~= 0
end

local function source_is_kind(src, kind)
	-- kind: "video_input", "audio_input", "media_like", "overlay_like"
	local id = obs.obs_source_get_id(src)
	local typ = obs.obs_source_get_type(src)
	local has_video = source_has_video_flags(src)
	local has_audio = source_has_audio_flags(src)

	if kind == "video_input" then
		if typ ~= obs.OBS_SOURCE_TYPE_INPUT then return false end
		if not has_video then return false end
		-- Exclude common non-camera static/video file sources
		if id == "image_source" or id == "browser_source" or id == "text_gdiplus" or id == "text_ft2_source" then
			return false
		end
		return true
	elseif kind == "audio_input" then
		if typ ~= obs.OBS_SOURCE_TYPE_INPUT then return false end
		return has_audio
	elseif kind == "media_like" then
		if id == "ffmpeg_source" or id == "vlc_source" then return true end
		return false
	elseif kind == "overlay_like" then
		if id == "browser_source" or id == "text_gdiplus" or id == "text_ft2_source" then return true end
		return false
	end

	return false
end

local function fill_source_list_property(prop, kind)
	obs.obs_property_list_clear(prop)
	obs.obs_property_list_add_string(prop, "(None)", "")

	local sources = obs.obs_enum_sources()
	if sources ~= nil then
		for _, src in ipairs(sources) do
			if source_is_kind(src, kind) then
				local n = obs.obs_source_get_name(src)
				obs.obs_property_list_add_string(prop, n, n)
			end
		end
		obs.source_list_release(sources)
	end
end

local function fill_scene_list_property(prop)
	obs.obs_property_list_clear(prop)
	obs.obs_property_list_add_string(prop, "(None)", "")

	local scenes = obs.obs_frontend_get_scenes()
	if scenes ~= nil then
		for _, sc in ipairs(scenes) do
			local name = obs.obs_source_get_name(sc)
			obs.obs_property_list_add_string(prop, name, name)
		end
		obs.source_list_release(scenes)
	end
end

local function fill_preset_name_property(prop)
	obs.obs_property_list_clear(prop)
	for name, _ in pairs(NAMED_PRESETS) do
		obs.obs_property_list_add_string(prop, name, name)
	end
end

local function fill_color_presets_property(prop)
	obs.obs_property_list_clear(prop)
	for _, p in ipairs(COLOR_PRESETS) do
		obs.obs_property_list_add_string(prop, p.name, p.name)
	end
end

--------------------------------------------------------------------------------
-- Filter management
--------------------------------------------------------------------------------

local function get_filter_by_name(source, filter_name)
	return obs.obs_source_get_filter_by_name(source, filter_name)
end

local function remove_filter_if_exists(source, filter_name)
	local f = get_filter_by_name(source, filter_name)
	if f ~= nil then
		obs.obs_source_filter_remove(source, f)
		obs.obs_source_release(f)
	end
end

local function update_filter_settings(filter, tbl)
	local data = create_data_from_table(tbl)
	obs.obs_source_update(filter, data)
	obs.obs_data_release(data)
end

local function ensure_filter(source, filter_id, filter_name, settings_tbl)
	local f = get_filter_by_name(source, filter_name)
	if f == nil then
		local data = create_data_from_table(settings_tbl or {})
		f = obs.obs_source_create_private(filter_id, filter_name, data)
		obs.obs_data_release(data)
		if f == nil then
			return nil, false
		end
		obs.obs_source_filter_add(source, f)
		return f, true
	else
		update_filter_settings(f, settings_tbl or {})
		return f, false
	end
end

local function detect_bg_filter_id_for_source(source)
	-- 1) Probe existing filters
	local flist = obs.obs_source_enum_filters(source)
	if flist ~= nil then
		for _, f in ipairs(flist) do
			local id = obs.obs_source_get_id(f)
			for _, cand in ipairs(BG_FILTER_CANDIDATES) do
				if id == cand then
					obs.source_list_release(flist)
					return cand
				end
			end
		end
		obs.source_list_release(flist)
	end

	-- 2) Probe by create_private
	for _, cand in ipairs(BG_FILTER_CANDIDATES) do
		local ok, tmp = pcall(function()
			local d = obs.obs_data_create()
			local t = obs.obs_source_create_private(cand, "__cst_probe_bg__", d)
			obs.obs_data_release(d)
			return t
		end)
		if ok and tmp ~= nil then
			obs.obs_source_release(tmp)
			return cand
		end
	end
	return nil
end

local function bg_threshold_value(preset)
	if preset == "Soft" then return 0.40 end
	if preset == "Aggressive" then return 0.72 end
	return 0.56 -- Balanced
end

local function best_effort_order_tint_last(source, tint_filter)
	-- Best effort: move tint toward bottom (later in stack) if API supports ordering.
	if obs.obs_source_filter_set_order ~= nil and obs.OBS_ORDER_MOVE_BOTTOM ~= nil then
		pcall(function()
			obs.obs_source_filter_set_order(source, tint_filter, obs.OBS_ORDER_MOVE_BOTTOM)
		end)
	end
end

local function apply_silhouette_pipeline()
	if st.webcam_source == "" then
		logw("No webcam source selected. Pipeline skipped.")
		return false
	end

	local ok = with_source(st.webcam_source, function(src)
		local base_color = preset_color_by_name(st.silhouette_preset)
		local opacity = clamp(st.opacity, 0, 100)
		local glow_strength = st.glow_enable and 35 or 0
		local outline_strength = st.outline_enable and 25 or 0

		-- Auto color optimization for cleaner silhouette
		local auto_settings = {
			brightness = 0.03,
			contrast = 0.18,
			saturation = 0.22,
			gamma = 0.98
		}

		-- Main tint
		local tint_settings = {
			color = base_color,
			opacity = opacity
		}

		-- Glow layers
		local glow_a_settings = {
			color = base_color,
			opacity = math.floor(opacity * 0.55),
			saturation = 0.35,
			contrast = 0.12
		}

		local glow_b_settings = {
			color = lerp_color(base_color, 0xFFFFFFFF, 0.24),
			opacity = math.floor(opacity * 0.30),
			saturation = 0.20,
			contrast = 0.08
		}

		-- Strobe "safety" filter kept subtle and toggled on peaks only
		local strobe_settings = {
			brightness = 0.00,
			contrast = 0.00,
			gamma = 1.00,
			opacity = 0
		}

		local auto_f, _ = ensure_filter(src, "color_filter", FILTER_AUTO, auto_settings)
		if auto_f == nil then
			logw("Could not create/update " .. FILTER_AUTO .. " (color_filter).")
		else
			obs.obs_source_set_enabled(auto_f, true)
		end

		local tint_f, _ = ensure_filter(src, "color_filter", FILTER_TINT, tint_settings)
		if tint_f == nil then
			logw("Could not create/update " .. FILTER_TINT .. " (color_filter).")
		else
			obs.obs_source_set_enabled(tint_f, true)
		end

		-- Glow and outline via layered color filters
		local glow_a_f, _ = ensure_filter(src, "color_filter", FILTER_GLOW_A, glow_a_settings)
		local glow_b_f, _ = ensure_filter(src, "color_filter", FILTER_GLOW_B, glow_b_settings)

		if glow_a_f ~= nil then
			obs.obs_source_set_enabled(glow_a_f, st.glow_enable or st.outline_enable)
		end
		if glow_b_f ~= nil then
			obs.obs_source_set_enabled(glow_b_f, st.glow_enable)
		end

		-- Use one extra filter to add edge punch if outline is enabled
		if outline_strength > 0 then
			local edge_settings = {
				sharpness = 0.38
			}
			local edge_f, _ = ensure_filter(src, "sharpness_filter", "CST Outline Sharpness", edge_settings)
			if edge_f ~= nil then
				obs.obs_source_set_enabled(edge_f, true)
				obs.obs_source_release(edge_f)
			end
		else
			remove_filter_if_exists(src, "CST Outline Sharpness")
		end

		-- Strobe filter
		local strobe_f, _ = ensure_filter(src, "color_filter", FILTER_STROBE, strobe_settings)
		if strobe_f ~= nil then
			obs.obs_source_set_enabled(strobe_f, st.strobe_enable)
		end

		-- Background removal plugin integration
		runtime.bg_filter_id = detect_bg_filter_id_for_source(src)
		if runtime.bg_filter_id ~= nil then
			local bg_settings = {
				threshold = bg_threshold_value(st.bg_threshold_preset)
			}
			local bg_f, created = ensure_filter(src, runtime.bg_filter_id, "CST Background Removal", bg_settings)
			if bg_f ~= nil then
				obs.obs_source_set_enabled(bg_f, st.bg_remove_enable)
				if created then
					logi("Background removal filter created using id '" .. runtime.bg_filter_id .. "'.")
				end
				obs.obs_source_release(bg_f)
			end
		else
			remove_filter_if_exists(src, "CST Background Removal")
		end

		-- Keep tint as the last style pass where API allows.
		if tint_f ~= nil then
			best_effort_order_tint_last(src, tint_f)
		end

		-- Release local refs returned by ensure_filter/get_filter_by_name.
		if auto_f ~= nil then obs.obs_source_release(auto_f) end
		if tint_f ~= nil then obs.obs_source_release(tint_f) end
		if glow_a_f ~= nil then obs.obs_source_release(glow_a_f) end
		if glow_b_f ~= nil then obs.obs_source_release(glow_b_f) end
		if strobe_f ~= nil then obs.obs_source_release(strobe_f) end

		return true
	end)

	if ok then
		logi("Silhouette/effects pipeline applied.")
		return true
	end
	return false
end

--------------------------------------------------------------------------------
-- Scene/source control
--------------------------------------------------------------------------------

local function set_scene_by_name(scene_name)
	if scene_name == nil or scene_name == "" then return false end

	local scenes = obs.obs_frontend_get_scenes()
	if scenes == nil then return false end

	local found = false
	for _, sc in ipairs(scenes) do
		local n = obs.obs_source_get_name(sc)
		if n == scene_name then
			obs.obs_frontend_set_current_scene(sc)
			found = true
			break
		end
	end
	obs.source_list_release(scenes)
	return found
end

local function get_current_scene_source()
	return obs.obs_frontend_get_current_scene()
end

local function find_scene_item_by_source_name(scene, source_name)
	if scene == nil or source_name == "" then return nil end
	local items = obs.obs_scene_enum_items(scene)
	if items == nil then return nil end

	local found = nil
	for _, item in ipairs(items) do
		local src = obs.obs_sceneitem_get_source(item)
		if src ~= nil then
			local n = obs.obs_source_get_name(src)
			if n == source_name then
				found = item
				break
			end
		end
	end

	obs.sceneitem_list_release(items)
	return found
end

local function is_source_visible_in_current_scene(source_name)
	local cur = get_current_scene_source()
	if cur == nil then return false end

	local scene = obs.obs_scene_from_source(cur)
	local visible = false
	local item = find_scene_item_by_source_name(scene, source_name)
	if item ~= nil then
		visible = obs.obs_sceneitem_visible(item)
	end

	obs.obs_source_release(cur)
	return visible
end

local function toggle_source_visibility_current_scene(source_name)
	if source_name == nil or source_name == "" then
		logw("No source selected for visibility toggle.")
		return false
	end

	local cur = get_current_scene_source()
	if cur == nil then return false end
	local scene = obs.obs_scene_from_source(cur)
	local item = find_scene_item_by_source_name(scene, source_name)

	local changed = false
	if item ~= nil then
		local vis = obs.obs_sceneitem_visible(item)
		obs.obs_sceneitem_set_visible(item, not vis)
		changed = true
	end
	obs.obs_source_release(cur)

	if changed then
		logi("Toggled visibility for '" .. source_name .. "'.")
	else
		logw("Source '" .. source_name .. "' not found in current scene.")
	end
	return changed
end

--------------------------------------------------------------------------------
-- Media controls
--------------------------------------------------------------------------------

local function media_play_pause()
	if st.media_source == "" then
		logw("No media source selected.")
		return
	end
	with_source(st.media_source, function(src)
		if obs.obs_source_media_get_state == nil or obs.obs_source_media_play_pause == nil then
			logw("Media controls are not available in this OBS build.")
			return
		end
		local state = obs.obs_source_media_get_state(src)
		-- 1=playing in common OBS builds; pause if playing, else play
		local pause = (state == 1)
		obs.obs_source_media_play_pause(src, pause)
		if pause then
			logi("Media paused: " .. st.media_source)
		else
			logi("Media playing: " .. st.media_source)
		end
	end)
end

local function media_next()
	if st.media_source == "" then
		logw("No media source selected.")
		return
	end
	with_source(st.media_source, function(src)
		if obs.obs_source_media_next == nil then
			logw("Media next control is not available in this OBS build.")
			return
		end
		obs.obs_source_media_next(src)
		logi("Media next: " .. st.media_source)
	end)
end

--------------------------------------------------------------------------------
-- Audio monitoring (best effort; degrades gracefully)
--------------------------------------------------------------------------------

local function estimate_audio_norm_from_db(db)
	-- Map roughly from -60..0 dB to 0..1
	local n = (db + 60.0) / 60.0
	return clamp(n, 0.0, 1.0)
end

local function on_audio_meter(...)
	-- OBS callback signatures can vary; this parser grabs best available number.
	local args = { ... }
	local peak = nil

	local function scan(v)
		if type(v) == "number" then
			if peak == nil or v > peak then peak = v end
		elseif type(v) == "table" then
			for _, x in pairs(v) do scan(x) end
		end
	end

	for _, a in ipairs(args) do
		scan(a)
	end

	if peak ~= nil then
		runtime.audio_db = clamp(peak, -60.0, 12.0)
		runtime.audio_norm = estimate_audio_norm_from_db(runtime.audio_db)
		runtime.last_voice_ts = now_s()
	end
end

local function detach_audio_meter()
	if runtime.meter ~= nil then
		if obs.obs_volmeter_detach_source ~= nil then
			pcall(function() obs.obs_volmeter_detach_source(runtime.meter) end)
		end
		if obs.obs_volmeter_remove_callback ~= nil then
			pcall(function() obs.obs_volmeter_remove_callback(runtime.meter, on_audio_meter, nil) end)
		end
		if obs.obs_volmeter_destroy ~= nil then
			pcall(function() obs.obs_volmeter_destroy(runtime.meter) end)
		end
		runtime.meter = nil
		runtime.meter_attached_source = ""
		runtime.audio_meter_supported = false
	end
end

local function attach_audio_meter_if_possible()
	if st.audio_source == "" then
		detach_audio_meter()
		return
	end
	if runtime.meter ~= nil and runtime.meter_attached_source == st.audio_source then
		return
	end

	detach_audio_meter()

	if obs.obs_volmeter_create == nil or obs.obs_volmeter_attach_source == nil or obs.obs_volmeter_add_callback == nil then
		runtime.audio_meter_supported = false
		logw("Audio meter API not available; reactive effects use fallback envelope.")
		return
	end

	with_source(st.audio_source, function(src)
		local meter = obs.obs_volmeter_create(obs.OBS_FADER_LOG)
		if meter == nil then
			runtime.audio_meter_supported = false
			logw("Failed to create audio meter.")
			return
		end

		obs.obs_volmeter_add_callback(meter, on_audio_meter, nil)
		obs.obs_volmeter_attach_source(meter, src)

		runtime.meter = meter
		runtime.meter_attached_source = st.audio_source
		runtime.audio_meter_supported = true
		logi("Audio meter attached to '" .. st.audio_source .. "'.")
	end)
end

--------------------------------------------------------------------------------
-- Presets
--------------------------------------------------------------------------------

local function apply_named_preset(name)
	local p = NAMED_PRESETS[name]
	if p == nil then
		logw("Preset '" .. tostring(name) .. "' not found.")
		return false
	end

	st.custom_color = p.color
	st.opacity = p.opacity
	st.glow_enable = p.glow
	st.outline_enable = p.outline
	st.reactive_enable = p.reactive
	st.random_burst_enable = p.random_burst
	st.strobe_enable = p.strobe
	st.cycle_enable = p.cycle
	st.cycle_seconds = p.cycle_seconds
	st.bg_remove_enable = p.bg_remove

	-- Match nearest built-in color name if possible
	local matched = false
	for _, cp in ipairs(COLOR_PRESETS) do
		if cp.color == p.color then
			st.silhouette_preset = cp.name
			matched = true
			break
		end
	end
	if not matched then
		st.silhouette_preset = "Electric Purple"
	end

	apply_silhouette_pipeline()
	logi("Loaded named preset: " .. name)
	return true
end

local function save_named_preset(name)
	if name == nil or name == "" then
		logw("Preset name cannot be empty.")
		return false
	end

	NAMED_PRESETS[name] = {
		color = st.custom_color,
		opacity = st.opacity,
		glow = st.glow_enable,
		outline = st.outline_enable,
		reactive = st.reactive_enable,
		random_burst = st.random_burst_enable,
		strobe = st.strobe_enable,
		cycle = st.cycle_enable,
		cycle_seconds = st.cycle_seconds,
		bg_remove = st.bg_remove_enable
	}

	st.selected_preset_name = name
	logi("Saved named preset: " .. name)
	return true
end

local function save_presets_to_settings(settings)
	local arr = obs.obs_data_array_create()
	for n, p in pairs(NAMED_PRESETS) do
		local item = obs.obs_data_create()
		obs.obs_data_set_string(item, "name", n)
		obs.obs_data_set_int(item, "color", p.color)
		obs.obs_data_set_int(item, "opacity", p.opacity)
		obs.obs_data_set_bool(item, "glow", p.glow)
		obs.obs_data_set_bool(item, "outline", p.outline)
		obs.obs_data_set_bool(item, "reactive", p.reactive)
		obs.obs_data_set_bool(item, "random_burst", p.random_burst)
		obs.obs_data_set_bool(item, "strobe", p.strobe)
		obs.obs_data_set_bool(item, "cycle", p.cycle)
		obs.obs_data_set_int(item, "cycle_seconds", p.cycle_seconds)
		obs.obs_data_set_bool(item, "bg_remove", p.bg_remove)
		obs.obs_data_array_push_back(arr, item)
		obs.obs_data_release(item)
	end
	obs.obs_data_set_array(settings, "named_presets", arr)
	obs.obs_data_array_release(arr)
end

local function load_presets_from_settings(settings)
	local arr = obs.obs_data_get_array(settings, "named_presets")
	if arr == nil then return end
	local count = obs.obs_data_array_count(arr)

	for i = 0, count - 1 do
		local item = obs.obs_data_array_item(arr, i)
		if item ~= nil then
			local name = obs.obs_data_get_string(item, "name")
			if name ~= nil and name ~= "" then
				NAMED_PRESETS[name] = {
					color = obs.obs_data_get_int(item, "color"),
					opacity = obs.obs_data_get_int(item, "opacity"),
					glow = obs.obs_data_get_bool(item, "glow"),
					outline = obs.obs_data_get_bool(item, "outline"),
					reactive = obs.obs_data_get_bool(item, "reactive"),
					random_burst = obs.obs_data_get_bool(item, "random_burst"),
					strobe = obs.obs_data_get_bool(item, "strobe"),
					cycle = obs.obs_data_get_bool(item, "cycle"),
					cycle_seconds = obs.obs_data_get_int(item, "cycle_seconds"),
					bg_remove = obs.obs_data_get_bool(item, "bg_remove")
				}
			end
			obs.obs_data_release(item)
		end
	end

	obs.obs_data_array_release(arr)
end

--------------------------------------------------------------------------------
-- High-level actions
--------------------------------------------------------------------------------

local function cycle_color_once()
	runtime.color_index = next_preset_index(runtime.color_index)
	local p = COLOR_PRESETS[runtime.color_index]
	st.silhouette_preset = p.name
	st.custom_color = p.color
	apply_silhouette_pipeline()
	logm("Cycle color -> " .. p.name)
end

local function random_crazy_mode()
	local idx = math.random(1, #COLOR_PRESETS)
	local p = COLOR_PRESETS[idx]
	runtime.color_index = idx

	st.silhouette_preset = p.name
	st.custom_color = p.color
	st.opacity = math.random(65, 98)
	st.glow_enable = true
	st.outline_enable = (math.random() > 0.25)
	st.reactive_enable = true
	st.random_burst_enable = true
	st.strobe_enable = (math.random() > 0.55)
	st.cycle_enable = (math.random() > 0.25)
	st.cycle_seconds = math.random(4, 12)
	st.bg_remove_enable = true

	apply_silhouette_pipeline()
	logm("Random Crazy Mode engaged: " .. p.name)
end

local function toggle_bg_removal()
	st.bg_remove_enable = not st.bg_remove_enable
	apply_silhouette_pipeline()
	if st.bg_remove_enable then
		logi("Background removal enabled.")
	else
		logi("Background removal disabled.")
	end
end

local function toggle_chat_overlay()
	if st.chat_overlay_source == "" then
		logw("No chat overlay source selected.")
		return
	end
	toggle_source_visibility_current_scene(st.chat_overlay_source)
end

local function run_health_check()
	logh("===== Health Check Start =====")
	local ok_count = 0
	local warn_count = 0

	-- Webcam source
	if st.webcam_source ~= "" then
		local exists = with_source(st.webcam_source, function(_) return true end)
		if exists then
			logh("Webcam source OK: " .. st.webcam_source)
			ok_count = ok_count + 1
		else
			logh("Webcam source missing: " .. st.webcam_source)
			warn_count = warn_count + 1
		end
	else
		logh("Webcam source not selected.")
		warn_count = warn_count + 1
	end

	-- Audio source
	if st.audio_source ~= "" then
		local exists = with_source(st.audio_source, function(_) return true end)
		if exists then
			logh("Audio source OK: " .. st.audio_source)
			ok_count = ok_count + 1
		else
			logh("Audio source missing: " .. st.audio_source)
			warn_count = warn_count + 1
		end
	else
		logh("Audio source not selected (reactive effects may be limited).")
		warn_count = warn_count + 1
	end

	-- Try applying pipeline and validate key filters
	local applied = apply_silhouette_pipeline()
	if applied then
		ok_count = ok_count + 1
	else
		warn_count = warn_count + 1
	end

	-- BG plugin diagnostics
	if runtime.bg_filter_id ~= nil then
		logh("Background removal plugin detected: " .. runtime.bg_filter_id)
		ok_count = ok_count + 1
	else
		logh("Background removal plugin not detected; feature gracefully disabled.")
		warn_count = warn_count + 1
	end

	-- Audio meter diagnostics
	attach_audio_meter_if_possible()
	if runtime.audio_meter_supported then
		logh("Audio monitoring active on: " .. runtime.meter_attached_source)
		ok_count = ok_count + 1
	else
		logh("Audio meter API unavailable in this OBS build (fallback pulse mode active).")
		warn_count = warn_count + 1
	end

	logh(string.format("Health summary: OK=%d WARN=%d", ok_count, warn_count))
	logh("===== Health Check End =====")
end

--------------------------------------------------------------------------------
-- Natural language parser + command application
--------------------------------------------------------------------------------

local function parse_seconds(text, fallback)
	local n = string.match(text, "(%d+)%s*second")
	if n ~= nil then
		local v = tonumber(n)
		if v ~= nil then return clamp(v, 1, 120) end
	end
	return fallback
end

local function apply_natural_language_command(cmd)
	local c = lower(cmd)
	if c == "" then
		logw("Natural Language command is empty.")
		return
	end

	local changes = 0

	-- Mode intents
	if contains(c, "gaming mode") or contains(c, "switch to gaming") then
		if apply_named_preset("Gaming") then changes = changes + 1 end
	elseif contains(c, "just chatting") then
		if apply_named_preset("Just Chatting") then changes = changes + 1 end
	elseif contains(c, "high energy") then
		if apply_named_preset("High Energy") then changes = changes + 1 end
	elseif contains(c, "chill") then
		if apply_named_preset("Chill") then changes = changes + 1 end
	end

	-- Color keywords
	local color_keywords = {
		["electric purple"] = "Electric Purple",
		["purple"] = "Electric Purple",
		["green"] = "Neon Green",
		["cyan"] = "Volt Cyan",
		["blue"] = "Cyber Blue",
		["pink"] = "Hot Pink",
		["red"] = "Laser Red",
		["yellow"] = "Acid Yellow",
		["orange"] = "Lava Orange",
		["teal"] = "Pulse Teal",
		["white"] = "Ghost White",
		["indigo"] = "Galaxy Indigo"
	}

	for k, pname in pairs(color_keywords) do
		if contains(c, k) then
			st.silhouette_preset = pname
			st.custom_color = preset_color_by_name(pname)
			changes = changes + 1
			break
		end
	end

	-- Cycle controls
	if contains(c, "cycle") then
		st.cycle_enable = not contains(c, "disable cycle") and not contains(c, "stop cycle")
		st.cycle_seconds = parse_seconds(c, st.cycle_seconds)
		changes = changes + 1
	end

	-- Reactive controls
	if contains(c, "reactive") or contains(c, "beat") or contains(c, "music") or contains(c, "voice") or contains(c, "sound") then
		st.reactive_enable = not contains(c, "disable reactive") and not contains(c, "no reactive")
		changes = changes + 1
	end

	-- Glow / outline
	if contains(c, "glow") then
		st.glow_enable = not contains(c, "disable glow") and not contains(c, "no glow")
		changes = changes + 1
	end
	if contains(c, "outline") then
		st.outline_enable = not contains(c, "disable outline") and not contains(c, "no outline")
		changes = changes + 1
	end

	-- Strobe / flash
	if contains(c, "strobe") or contains(c, "flash") then
		st.strobe_enable = not contains(c, "disable strobe") and not contains(c, "no strobe")
		changes = changes + 1
	end

	-- Random burst
	if contains(c, "random burst") or contains(c, "burst mode") then
		st.random_burst_enable = not contains(c, "disable random burst")
		changes = changes + 1
	end

	-- Background removal
	if contains(c, "remove background") or contains(c, "background removal") or contains(c, "green screen") then
		st.bg_remove_enable = not contains(c, "disable background removal")
		changes = changes + 1
	end

	-- Chat overlay
	if contains(c, "chat overlay") then
		toggle_chat_overlay()
		changes = changes + 1
	end

	-- Silhouette intensity hints
	if contains(c, "silhouette") then
		if contains(c, "strong") or contains(c, "intense") then
			st.opacity = 94
			changes = changes + 1
		elseif contains(c, "soft") or contains(c, "subtle") then
			st.opacity = 70
			changes = changes + 1
		end
	end

	-- Direct triggers
	if contains(c, "random crazy") then
		random_crazy_mode()
		changes = changes + 1
	elseif contains(c, "cycle color now") then
		cycle_color_once()
		changes = changes + 1
	end

	attach_audio_meter_if_possible()
	apply_silhouette_pipeline()

	logm(string.format("Applied NL command (%d change(s)): %s", changes, cmd))
end

--------------------------------------------------------------------------------
-- Runtime automation + effects tick
--------------------------------------------------------------------------------

local function estimated_cpu_gpu()
	-- Best-effort estimation from frame timing APIs if available.
	local fps = 0.0
	local frame_ns = 0.0

	if obs.obs_get_active_fps ~= nil then
		fps = tonumber(obs.obs_get_active_fps()) or 0.0
	end
	if obs.obs_get_average_frame_time_ns ~= nil then
		frame_ns = tonumber(obs.obs_get_average_frame_time_ns()) or 0.0
	end

	if fps <= 0.0 then
		return 0.0, 0.0
	end

	local budget_ns = 1000000000.0 / fps
	if budget_ns <= 0 then return 0.0, 0.0 end

	local load = clamp((frame_ns / budget_ns) * 100.0, 0.0, 100.0)
	-- OBS Lua does not expose direct GPU utilization everywhere, so mirror estimate.
	local cpu_est = load
	local gpu_est = clamp(load * 0.92 + 4.0, 0.0, 100.0)
	return cpu_est, gpu_est
end

local function apply_reactive_adjustments()
	if st.webcam_source == "" then return end

	-- Determine envelope:
	local env = runtime.audio_norm
	if not runtime.audio_meter_supported then
		-- Fallback soft pulse if meter unavailable
		runtime.pulse_phase = runtime.pulse_phase + 0.16
		env = 0.28 + 0.20 * (0.5 + 0.5 * math.sin(runtime.pulse_phase))
	end

	env = clamp(env, 0.0, 1.0)

	local base_color = preset_color_by_name(st.silhouette_preset)
	local hot_color = lerp_color(base_color, 0xFFFFFFFF, clamp(env * 0.35, 0, 0.35))
	local base_opacity = st.opacity
	local reactive_boost = st.reactive_enable and math.floor(env * 20) or 0
	local new_opacity = clamp(base_opacity + reactive_boost, 0, 100)

	with_source(st.webcam_source, function(src)
		local tint = get_filter_by_name(src, FILTER_TINT)
		if tint ~= nil then
			update_filter_settings(tint, {
				color = hot_color,
				opacity = new_opacity
			})
			obs.obs_source_release(tint)
		end

		local glowA = get_filter_by_name(src, FILTER_GLOW_A)
		if glowA ~= nil then
			update_filter_settings(glowA, {
				color = hot_color,
				opacity = clamp(math.floor(new_opacity * 0.55 + env * 20), 0, 100)
			})
			obs.obs_source_release(glowA)
		end

		local glowB = get_filter_by_name(src, FILTER_GLOW_B)
		if glowB ~= nil then
			update_filter_settings(glowB, {
				color = lerp_color(base_color, 0xFFFFFFFF, 0.24 + env * 0.20),
				opacity = clamp(math.floor(new_opacity * 0.30 + env * 15), 0, 100)
			})
			obs.obs_source_release(glowB)
		end

		-- Safety-limited strobe on peaks
		local peak = env > 0.82
		local ts = now_s()
		if st.strobe_enable and peak and (ts - runtime.last_strobe_ts) > 0.12 then
			runtime.last_strobe_ts = ts
			runtime.strobe_state = not runtime.strobe_state

			local strobe = get_filter_by_name(src, FILTER_STROBE)
			if strobe ~= nil then
				local val = runtime.strobe_state and 100 or 0
				update_filter_settings(strobe, {
					opacity = val,
					brightness = runtime.strobe_state and 0.10 or 0.00
				})
				obs.obs_source_set_enabled(strobe, true)
				obs.obs_source_release(strobe)
			end
		end
	end)
end

local function do_random_burst_if_needed()
	if not st.random_burst_enable then return end
	local ts = now_s()
	local trigger = runtime.audio_norm > 0.88
	if not trigger then return end
	if (ts - runtime.last_burst_ts) < 0.65 then return end

	runtime.last_burst_ts = ts
	local idx = math.random(1, #COLOR_PRESETS)
	local p = COLOR_PRESETS[idx]
	st.silhouette_preset = p.name
	st.custom_color = p.color

	with_source(st.webcam_source, function(src)
		local tint = get_filter_by_name(src, FILTER_TINT)
		if tint ~= nil then
			update_filter_settings(tint, { color = p.color, opacity = clamp(st.opacity + 12, 0, 100) })
			obs.obs_source_release(tint)
		end
	end)
end

local function do_cycle_if_needed()
	if not st.cycle_enable then return end
	local ts = now_s()
	local sec = clamp(st.cycle_seconds, 1, 120)
	if (ts - runtime.last_cycle_ts) >= sec then
		runtime.last_cycle_ts = ts
		cycle_color_once()
	end
end

local function do_scene_automation_if_needed()
	if not st.auto_scene_enable then return end

	local ts = now_s()
	local db = runtime.audio_db
	local talking = (db >= st.voice_threshold_db)

	if talking then
		runtime.last_voice_ts = ts
		if st.talking_scene ~= "" then
			set_scene_by_name(st.talking_scene)
		end
	else
		if st.waiting_scene ~= "" and (ts - runtime.last_voice_ts) > st.silence_seconds then
			set_scene_by_name(st.waiting_scene)
		end
	end
end

local function do_motion_automation_if_needed()
	if not st.motion_enable then return end
	if st.motion_source == "" or st.motion_scene == "" then return end

	local ts = now_s()
	if (ts - runtime.last_motion_ts) < 0.4 then return end
	runtime.last_motion_ts = ts

	if is_source_visible_in_current_scene(st.motion_source) then
		set_scene_by_name(st.motion_scene)
	end
end

local function do_diagnostics_if_needed()
	if not st.diagnostics_enable then return end

	local ts = now_s()
	if (ts - runtime.last_diag_ts) < 5.0 then return end
	runtime.last_diag_ts = ts

	local cpu, gpu = estimated_cpu_gpu()
	local meter_note = runtime.audio_meter_supported and "meter=live" or "meter=fallback"
	logi(string.format("Diag CPU~%.1f%% GPU~%.1f%% audio=%.1fdB (%s)", cpu, gpu, runtime.audio_db, meter_note))
end

local function main_tick()
	do_cycle_if_needed()
	apply_reactive_adjustments()
	do_random_burst_if_needed()
	do_scene_automation_if_needed()
	do_motion_automation_if_needed()
	do_diagnostics_if_needed()
end

--------------------------------------------------------------------------------
-- UI callbacks
--------------------------------------------------------------------------------

local function refresh_property_lists(props)
	if props == nil then return end

	local p_webcam = obs.obs_properties_get(props, "webcam_source")
	local p_audio = obs.obs_properties_get(props, "audio_source")
	local p_media = obs.obs_properties_get(props, "media_source")
	local p_chat = obs.obs_properties_get(props, "chat_overlay_source")
	local p_motion = obs.obs_properties_get(props, "motion_source")

	local p_talking = obs.obs_properties_get(props, "talking_scene")
	local p_waiting = obs.obs_properties_get(props, "waiting_scene")
	local p_motion_scene = obs.obs_properties_get(props, "motion_scene")

	local p_color_presets = obs.obs_properties_get(props, "silhouette_preset")
	local p_named = obs.obs_properties_get(props, "selected_preset_name")

	if p_webcam ~= nil then fill_source_list_property(p_webcam, "video_input") end
	if p_audio ~= nil then fill_source_list_property(p_audio, "audio_input") end
	if p_media ~= nil then fill_source_list_property(p_media, "media_like") end
	if p_chat ~= nil then fill_source_list_property(p_chat, "overlay_like") end
	if p_motion ~= nil then fill_source_list_property(p_motion, "video_input") end

	if p_talking ~= nil then fill_scene_list_property(p_talking) end
	if p_waiting ~= nil then fill_scene_list_property(p_waiting) end
	if p_motion_scene ~= nil then fill_scene_list_property(p_motion_scene) end

	if p_color_presets ~= nil then fill_color_presets_property(p_color_presets) end
	if p_named ~= nil then fill_preset_name_property(p_named) end
end

local function cb_refresh(props, p)
	refresh_property_lists(props)
	logi("Source/scene lists refreshed.")
	return true
end

local function cb_apply_magic(props, p)
	local cmd = st.nl_command or ""
	apply_natural_language_command(cmd)
	return true
end

local function cb_cycle(props, p)
	cycle_color_once()
	return true
end

local function cb_random(props, p)
	random_crazy_mode()
	return true
end

local function cb_health(props, p)
	run_health_check()
	return true
end

local function cb_save_preset(props, p)
	local name = st.selected_preset_name
	save_named_preset(name)
	refresh_property_lists(props)
	return true
end

local function cb_load_preset(props, p)
	apply_named_preset(st.selected_preset_name)
	return true
end

local function cb_media_pp(props, p)
	media_play_pause()
	return true
end

local function cb_media_next(props, p)
	media_next()
	return true
end

local function cb_chat_toggle(props, p)
	toggle_chat_overlay()
	return true
end

local function cb_assign_hotkeys(props, p)
	-- OBS does not expose a stable Lua API to assign key combos directly across all builds.
	-- We register all hotkeys with clear labels so users can bind them quickly in OBS Hotkeys.
	logi("Hotkeys registered. Assign recommended combos in Settings -> Hotkeys:")
	logi("CST: Cycle Color=Ctrl+Shift+C | Random Crazy=Ctrl+Shift+R | Apply Magic=Ctrl+Shift+M")
	logi("CST: Toggle BG=Ctrl+Shift+B | Toggle Chat=Ctrl+Shift+O")
	logi("CST: Media Play/Pause=Ctrl+Shift+P | Media Next=Ctrl+Shift+N | Health Check=Ctrl+Shift+H")
	return true
end

--------------------------------------------------------------------------------
-- Hotkeys
--------------------------------------------------------------------------------

local function hk_cycle(pressed)
	if not pressed then return end
	cycle_color_once()
end

local function hk_random(pressed)
	if not pressed then return end
	random_crazy_mode()
end

local function hk_bg(pressed)
	if not pressed then return end
	toggle_bg_removal()
end

local function hk_chat(pressed)
	if not pressed then return end
	toggle_chat_overlay()
end

local function hk_media_pp(pressed)
	if not pressed then return end
	media_play_pause()
end

local function hk_media_next(pressed)
	if not pressed then return end
	media_next()
end

local function hk_health(pressed)
	if not pressed then return end
	run_health_check()
end

local function hk_magic(pressed)
	if not pressed then return end
	apply_natural_language_command(st.nl_command or "")
end

local function register_hotkeys()
	hotkeys.cycle.id = obs.obs_hotkey_register_frontend("cst.cycle_color", "CST: Cycle Color", hk_cycle)
	hotkeys.random.id = obs.obs_hotkey_register_frontend("cst.random_crazy", "CST: Random Crazy Mode", hk_random)
	hotkeys.bg_toggle.id = obs.obs_hotkey_register_frontend("cst.toggle_bg", "CST: Toggle Background Removal", hk_bg)
	hotkeys.chat_toggle.id = obs.obs_hotkey_register_frontend("cst.toggle_chat", "CST: Toggle Chat Overlay", hk_chat)
	hotkeys.media_pp.id = obs.obs_hotkey_register_frontend("cst.media_pp", "CST: Media Play/Pause", hk_media_pp)
	hotkeys.media_next.id = obs.obs_hotkey_register_frontend("cst.media_next", "CST: Media Next", hk_media_next)
	hotkeys.health.id = obs.obs_hotkey_register_frontend("cst.health", "CST: Health Check", hk_health)
	hotkeys.magic.id = obs.obs_hotkey_register_frontend("cst.apply_magic", "CST: Apply Magic (NL)", hk_magic)

	if settings_ref ~= nil then
		for _, h in pairs(hotkeys) do
			local a = obs.obs_data_get_array(settings_ref, h.key)
			obs.obs_hotkey_load(h.id, a)
			obs.obs_data_array_release(a)
		end
	end
end

--------------------------------------------------------------------------------
-- OBS script lifecycle
--------------------------------------------------------------------------------

function script_description()
	return [[
Crazy Streamer Tool (Single-file Swiss-army script) v1.0.0

Features:
- Advanced colored silhouette engine with 20+ presets + custom ARGB
- Sound reactive glow/pulse/outline + cycle/random/strobe effects (safety-limited)
- Natural Language command box: type plain English and hit Apply Magic
- Background removal plugin integration (auto-detect + graceful fallback)
- Scene/source automation (voice activity + basic motion visibility trigger)
- Media/chat overlay controls
- Named preset save/load system
- Health check and diagnostics logging
- Persistent hotkeys across OBS restarts

Quick start:
1) Select Webcam + Audio source
2) Pick a silhouette preset
3) Optional: enable BG removal/reactive/cycle
4) Try NL command: "switch to gaming mode with green outline"

Emoji help:
- Magic: ✨
- Health: 🩺
- Reactive: 🔊
- Presets: 🎨
]]
end

function script_defaults(settings)
	obs.obs_data_set_string(settings, "webcam_source", "")
	obs.obs_data_set_string(settings, "audio_source", "")
	obs.obs_data_set_string(settings, "media_source", "")
	obs.obs_data_set_string(settings, "chat_overlay_source", "")
	obs.obs_data_set_string(settings, "motion_source", "")

	obs.obs_data_set_string(settings, "talking_scene", "")
	obs.obs_data_set_string(settings, "waiting_scene", "")
	obs.obs_data_set_string(settings, "motion_scene", "")

	obs.obs_data_set_string(settings, "silhouette_preset", "Electric Purple")
	obs.obs_data_set_int(settings, "custom_color", 0xFFFF00FF)
	obs.obs_data_set_int(settings, "opacity", 85)
	obs.obs_data_set_bool(settings, "glow_enable", true)
	obs.obs_data_set_bool(settings, "outline_enable", true)
	obs.obs_data_set_bool(settings, "reactive_enable", true)
	obs.obs_data_set_bool(settings, "random_burst_enable", false)
	obs.obs_data_set_bool(settings, "strobe_enable", false)

	obs.obs_data_set_bool(settings, "cycle_enable", false)
	obs.obs_data_set_int(settings, "cycle_seconds", 8)

	obs.obs_data_set_bool(settings, "bg_remove_enable", false)
	obs.obs_data_set_string(settings, "bg_threshold_preset", "Balanced")

	obs.obs_data_set_bool(settings, "auto_scene_enable", false)
	obs.obs_data_set_int(settings, "silence_seconds", 4)
	obs.obs_data_set_double(settings, "voice_threshold_db", -34.0)
	obs.obs_data_set_bool(settings, "motion_enable", false)

	obs.obs_data_set_string(settings, "nl_command", "")
	obs.obs_data_set_string(settings, "selected_preset_name", "Just Chatting")

	obs.obs_data_set_bool(settings, "diagnostics_enable", true)
end

function script_properties()
	local props = obs.obs_properties_create()

	-- Top section
	obs.obs_properties_add_text(
		props,
		"hdr_top",
		"Crazy Streamer Tool Control Panel",
		obs.OBS_TEXT_INFO
	)

	local p_webcam = obs.obs_properties_add_list(props, "webcam_source", "Webcam Source",
		obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
	local p_audio = obs.obs_properties_add_list(props, "audio_source", "Audio Source (Reactive Input)",
		obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
	local p_media = obs.obs_properties_add_list(props, "media_source", "Media Source",
		obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
	local p_chat = obs.obs_properties_add_list(props, "chat_overlay_source", "Chat Overlay Source",
		obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
	local p_motion = obs.obs_properties_add_list(props, "motion_source", "Motion Trigger Source",
		obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)

	fill_source_list_property(p_webcam, "video_input")
	fill_source_list_property(p_audio, "audio_input")
	fill_source_list_property(p_media, "media_like")
	fill_source_list_property(p_chat, "overlay_like")
	fill_source_list_property(p_motion, "video_input")

	obs.obs_properties_add_button(props, "btn_refresh", "Refresh Source List", cb_refresh)

	-- Silhouette & Effects group
	local g_sil = obs.obs_properties_create()
	local p_color = obs.obs_properties_add_list(g_sil, "silhouette_preset", "Color Preset",
		obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
	fill_color_presets_property(p_color)

	obs.obs_properties_add_color(g_sil, "custom_color", "Custom Color (ARGB)")
	obs.obs_properties_add_int_slider(g_sil, "opacity", "Opacity", 0, 100, 1)
	obs.obs_properties_add_bool(g_sil, "glow_enable", "Enable Glow")
	obs.obs_properties_add_bool(g_sil, "outline_enable", "Enable Outline")
	obs.obs_properties_add_bool(g_sil, "reactive_enable", "Enable Sound Reactive Pulse")
	obs.obs_properties_add_bool(g_sil, "random_burst_enable", "Enable Random Color Burst")
	obs.obs_properties_add_bool(g_sil, "strobe_enable", "Enable Strobe on Peaks (Safety Limited)")

	obs.obs_properties_add_bool(g_sil, "cycle_enable", "Enable Auto Color Cycle")
	obs.obs_properties_add_int_slider(g_sil, "cycle_seconds", "Cycle Period (seconds)", 1, 120, 1)

	local g_bg = obs.obs_properties_create()
	obs.obs_properties_add_bool(g_bg, "bg_remove_enable", "Enable Background Removal")
	local p_bgp = obs.obs_properties_add_list(g_bg, "bg_threshold_preset", "Threshold Preset",
		obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
	obs.obs_property_list_add_string(p_bgp, "Soft", "Soft")
	obs.obs_property_list_add_string(p_bgp, "Balanced", "Balanced")
	obs.obs_property_list_add_string(p_bgp, "Aggressive", "Aggressive")

	obs.obs_properties_add_group(g_sil, "bg_group", "Smart Background Removal Integration",
		obs.OBS_GROUP_NORMAL, g_bg)

	obs.obs_properties_add_group(props, "sil_group", "Silhouette & Effects",
		obs.OBS_GROUP_NORMAL, g_sil)

	-- Automation group
	local g_auto = obs.obs_properties_create()
	obs.obs_properties_add_bool(g_auto, "auto_scene_enable", "Enable Voice Activity Scene Switch")
	local p_talking = obs.obs_properties_add_list(g_auto, "talking_scene", "Talking Scene",
		obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
	local p_waiting = obs.obs_properties_add_list(g_auto, "waiting_scene", "Waiting Scene",
		obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
	fill_scene_list_property(p_talking)
	fill_scene_list_property(p_waiting)

	obs.obs_properties_add_float_slider(g_auto, "voice_threshold_db", "Voice Threshold (dB)", -60.0, -5.0, 1.0)
	obs.obs_properties_add_int_slider(g_auto, "silence_seconds", "Silence Delay (s)", 1, 60, 1)

	obs.obs_properties_add_bool(g_auto, "motion_enable", "Enable Motion Trigger (Source Visibility)")
	local p_motion_scene = obs.obs_properties_add_list(g_auto, "motion_scene", "Motion Scene",
		obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
	fill_scene_list_property(p_motion_scene)

	obs.obs_properties_add_group(props, "automation_group", "Automation",
		obs.OBS_GROUP_NORMAL, g_auto)

	-- Chat & Media group
	local g_chat_media = obs.obs_properties_create()
	obs.obs_properties_add_button(g_chat_media, "btn_chat_toggle", "Toggle Chat Overlay", cb_chat_toggle)
	obs.obs_properties_add_button(g_chat_media, "btn_media_pp", "Media Play/Pause", cb_media_pp)
	obs.obs_properties_add_button(g_chat_media, "btn_media_next", "Media Next", cb_media_next)
	obs.obs_properties_add_group(props, "chat_media_group", "Chat & Media",
		obs.OBS_GROUP_NORMAL, g_chat_media)

	-- Presets group
	local g_preset = obs.obs_properties_create()
	obs.obs_properties_add_text(g_preset, "selected_preset_name", "Preset Name", obs.OBS_TEXT_DEFAULT)
	local p_named = obs.obs_properties_add_list(g_preset, "selected_preset_name", "Load Preset",
		obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
	fill_preset_name_property(p_named)
	obs.obs_properties_add_button(g_preset, "btn_save_preset", "Save Preset", cb_save_preset)
	obs.obs_properties_add_button(g_preset, "btn_load_preset", "Load Preset", cb_load_preset)
	obs.obs_properties_add_group(props, "preset_group", "Presets",
		obs.OBS_GROUP_NORMAL, g_preset)

	-- Natural Language box
	local g_nl = obs.obs_properties_create()
	obs.obs_properties_add_text(g_nl, "nl_command", "Natural Language Command", obs.OBS_TEXT_MULTILINE)
	obs.obs_properties_add_button(g_nl, "btn_apply_magic", "Apply Magic", cb_apply_magic)
	obs.obs_properties_add_group(props, "nl_group", "Natural Language Command Box",
		obs.OBS_GROUP_NORMAL, g_nl)

	-- Bottom controls
	obs.obs_properties_add_button(props, "btn_cycle", "Cycle Color", cb_cycle)
	obs.obs_properties_add_button(props, "btn_random", "Random Crazy Mode", cb_random)
	obs.obs_properties_add_button(props, "btn_health", "Health Check", cb_health)
	obs.obs_properties_add_button(props, "btn_assign_hotkeys", "Assign All Recommended Hotkeys", cb_assign_hotkeys)
	obs.obs_properties_add_bool(props, "diagnostics_enable", "Enable Live Diagnostics Logging")

	return props
end

function script_update(settings)
	settings_ref = settings

	st.webcam_source = obs.obs_data_get_string(settings, "webcam_source")
	st.audio_source = obs.obs_data_get_string(settings, "audio_source")
	st.media_source = obs.obs_data_get_string(settings, "media_source")
	st.chat_overlay_source = obs.obs_data_get_string(settings, "chat_overlay_source")
	st.motion_source = obs.obs_data_get_string(settings, "motion_source")

	st.talking_scene = obs.obs_data_get_string(settings, "talking_scene")
	st.waiting_scene = obs.obs_data_get_string(settings, "waiting_scene")
	st.motion_scene = obs.obs_data_get_string(settings, "motion_scene")

	st.silhouette_preset = obs.obs_data_get_string(settings, "silhouette_preset")
	st.custom_color = obs.obs_data_get_int(settings, "custom_color")
	st.opacity = obs.obs_data_get_int(settings, "opacity")
	st.glow_enable = obs.obs_data_get_bool(settings, "glow_enable")
	st.outline_enable = obs.obs_data_get_bool(settings, "outline_enable")
	st.reactive_enable = obs.obs_data_get_bool(settings, "reactive_enable")
	st.random_burst_enable = obs.obs_data_get_bool(settings, "random_burst_enable")
	st.strobe_enable = obs.obs_data_get_bool(settings, "strobe_enable")

	st.cycle_enable = obs.obs_data_get_bool(settings, "cycle_enable")
	st.cycle_seconds = obs.obs_data_get_int(settings, "cycle_seconds")

	st.bg_remove_enable = obs.obs_data_get_bool(settings, "bg_remove_enable")
	st.bg_threshold_preset = obs.obs_data_get_string(settings, "bg_threshold_preset")

	st.auto_scene_enable = obs.obs_data_get_bool(settings, "auto_scene_enable")
	st.silence_seconds = obs.obs_data_get_int(settings, "silence_seconds")
	st.voice_threshold_db = obs.obs_data_get_double(settings, "voice_threshold_db")
	st.motion_enable = obs.obs_data_get_bool(settings, "motion_enable")

	st.nl_command = obs.obs_data_get_string(settings, "nl_command")
	st.selected_preset_name = obs.obs_data_get_string(settings, "selected_preset_name")
	st.diagnostics_enable = obs.obs_data_get_bool(settings, "diagnostics_enable")

	attach_audio_meter_if_possible()
	apply_silhouette_pipeline()
end

function script_load(settings)
	settings_ref = settings
	load_presets_from_settings(settings)
	register_hotkeys()

	runtime.last_cycle_ts = now_s()
	runtime.last_voice_ts = now_s()
	runtime.last_diag_ts = now_s()

	obs.timer_add(main_tick, 100)
	attach_audio_meter_if_possible()
	apply_silhouette_pipeline()

	logi("Loaded " .. SCRIPT_TAG .. " version " .. SCRIPT_VER)
end

function script_save(settings)
	save_presets_to_settings(settings)
	for _, h in pairs(hotkeys) do
		local a = obs.obs_hotkey_save(h.id)
		obs.obs_data_set_array(settings, h.key, a)
		obs.obs_data_array_release(a)
	end
end

function script_unload()
	obs.timer_remove(main_tick)
	detach_audio_meter()
	logi("Unloaded " .. SCRIPT_TAG)
end
