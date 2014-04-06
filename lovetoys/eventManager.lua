EventManager = class("EventManager")

function EventManager:__init()
    self.eventListeners = {}
end

-- Adding an eventlistener to a specific event
function EventManager:addListener(eventName, listener)
    if not self.eventListeners[eventName] then
        self.eventListeners[eventName] = {}
    end
    table.insert(self.eventListeners[eventName], listener)
end

-- Removing an eventlistener from an event
function EventManager:removeListener(eventName, listener)
    if self.eventListeners[eventName] then
        for key, value in pairs(self.eventListener[eventName]) do
            if value[1].__name == listener then
                table.remove(self.eventListener[eventName], key)
                break
            end
        end
    end
end

-- Firing an event. All registered listener will react to this event
function EventManager:fireEvent(event)
    if self.eventListeners[event.__name] then
        for k,v in pairs(self.eventListeners[event.__name]) do
            v[2](v[1], event)
        end
    end
end

