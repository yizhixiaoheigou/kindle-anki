-- Day-granularity SM-2 variant for Kindle Anki.
local Schedule = {}

Schedule.RATING_AGAIN = "again"
Schedule.RATING_HARD = "hard"
Schedule.RATING_GOOD = "good"
Schedule.RATING_EASY = "easy"
Schedule.MAX_INTERVAL_DAYS = 36500
Schedule.AGAIN_SECONDS = 10 * 60

local function clamp_interval(value)
    if value > Schedule.MAX_INTERVAL_DAYS then return Schedule.MAX_INTERVAL_DAYS end
    if value < 1 then return 1 end
    return math.floor(value)
end

function Schedule.today()
    -- Local civil day number since Unix epoch (UTC-based day index is fine for V1).
    return math.floor(os.time() / 86400)
end

function Schedule.default_state()
    return {
        due = 0,
        due_at = nil,
        interval = 0,
        reps = 0,
        lapses = 0,
        last_rating = nil,
        reviewed_at = nil,
        extra = false,
        starred = false,
    }
end

function Schedule.is_new(state)
    return state and (tonumber(state.reps) or 0) == 0 and (tonumber(state.lapses) or 0) == 0
end

function Schedule.is_due(state, today, now)
    today = today or Schedule.today()
    now = now or os.time()
    if Schedule.is_new(state) then return false end
    local due_at = tonumber(state.due_at)
    if due_at and due_at > now then return false end
    return (tonumber(state.due) or 0) <= today
end

function Schedule.next_interval(interval, rating)
    local base = tonumber(interval) or 0
    if rating == Schedule.RATING_AGAIN then
        return 0
    elseif rating == Schedule.RATING_HARD then
        return clamp_interval(base == 0 and 1 or base * 6 / 5 + 1)
    elseif rating == Schedule.RATING_GOOD then
        return clamp_interval(base == 0 and 1 or base * 5 / 2 + 1)
    elseif rating == Schedule.RATING_EASY then
        return clamp_interval(base == 0 and 4 or base * 7 / 2 + 1)
    end
    return base
end

function Schedule.preview_days(interval, rating)
    if rating == Schedule.RATING_AGAIN then return 0 end
    return Schedule.next_interval(interval, rating)
end

function Schedule.apply(state, rating, today, as_extra, now)
    today = today or Schedule.today()
    now = now or os.time()
    state = state or Schedule.default_state()
    if rating == "skipped" then
        return state
    end
    if rating == Schedule.RATING_AGAIN then
        state.interval = 0
        state.lapses = math.min(65535, (tonumber(state.lapses) or 0) + 1)
        state.due = today
        state.due_at = now + Schedule.AGAIN_SECONDS
    else
        state.interval = Schedule.next_interval(state.interval, rating)
        state.reps = math.min(65535, (tonumber(state.reps) or 0) + 1)
        state.due = today + (tonumber(state.interval) or 0)
        state.due_at = nil
    end
    state.last_rating = rating
    state.reviewed_at = now
    if as_extra then state.extra = true end
    return state
end

function Schedule.preview_label(interval, rating)
    local days = Schedule.preview_days(interval, rating)
    if days == 0 then return "today" end
    return tostring(days) .. "d"
end

return Schedule
