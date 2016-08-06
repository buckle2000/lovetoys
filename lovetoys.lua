local middleclass = {
    _VERSION     = 'middleclass v3.0.1',
    _DESCRIPTION = 'Object Orientation for Lua',
    _URL         = 'https://github.com/kikito/middleclass',
    _LICENSE     = [[
    MIT LICENSE

    Copyright (c) 2011 Enrique García Cota

    Permission is hereby granted, free of charge, to any person obtaining a
    copy of this software and associated documentation files (the
    "Software"), to deal in the Software without restriction, including
    without limitation the rights to use, copy, modify, merge, publish,
    distribute, sublicense, and/or sell copies of the Software, and to
    permit persons to whom the Software is furnished to do so, subject to
    the following conditions:

    The above copyright notice and this permission notice shall be included
    in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
    OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
    IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
    CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
    TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
    SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    ]]
}

local function _setClassDictionariesMetatables(aClass)
    local dict = aClass.__instanceDict
    dict.__index = dict

    local super = aClass.super
    if super then
        local superStatic = super.static
        setmetatable(dict, super.__instanceDict)
        setmetatable(aClass.static, { __index = function(_,k) return dict[k] or superStatic[k] end })
    else
        setmetatable(aClass.static, { __index = function(_,k) return dict[k] end })
    end
end

local function _setClassMetatable(aClass)
    setmetatable(aClass, {
        __tostring = function() return "class " .. aClass.name end,
        __index    = aClass.static,
        __newindex = aClass.__instanceDict,
        __call     = function(self, ...) return self:new(...) end
    })
end

local function _createClass(name, super)
    local aClass = { name = name, super = super, static = {}, __mixins = {}, __instanceDict={} }
    aClass.subclasses = setmetatable({}, {__mode = "k"})

    _setClassDictionariesMetatables(aClass)
    _setClassMetatable(aClass)

    return aClass
end

local function _createLookupMetamethod(aClass, name)
    return function(...)
        local method = aClass.super[name]
        assert( type(method)=='function', tostring(aClass) .. " doesn't implement metamethod '" .. name .. "'" )
        return method(...)
    end
end

local function _setClassMetamethods(aClass)
    for _,m in ipairs(aClass.__metamethods) do
        aClass[m]= _createLookupMetamethod(aClass, m)
    end
end

local function _setDefaultInitializeMethod(aClass, super)
    aClass.initialize = function(instance, ...)
        return super.initialize(instance, ...)
    end
end

local function _includeMixin(aClass, mixin)
    assert(type(mixin)=='table', "mixin must be a table")
    for name,method in pairs(mixin) do
        if name ~= "included" and name ~= "static" then aClass[name] = method end
    end
    if mixin.static then
        for name,method in pairs(mixin.static) do
            aClass.static[name] = method
        end
    end
    if type(mixin.included)=="function" then mixin:included(aClass) end
    aClass.__mixins[mixin] = true
end

local Object = _createClass("Object", nil)

Object.static.__metamethods = { '__add', '__call', '__concat', '__div', '__ipairs', '__le',
'__len', '__lt', '__mod', '__mul', '__pairs', '__pow', '__sub',
'__tostring', '__unm'}

function Object.static:allocate()
    assert(type(self) == 'table', "Make sure that you are using 'Class:allocate' instead of 'Class.allocate'")
    return setmetatable({ class = self }, self.__instanceDict)
end

function Object.static:new(...)
    local instance = self:allocate()
    instance:initialize(...)
    return instance
end

function Object.static:subclass(name)
    assert(type(self) == 'table', "Make sure that you are using 'Class:subclass' instead of 'Class.subclass'")
    assert(type(name) == "string", "You must provide a name(string) for your class")

    local subclass = _createClass(name, self)
    _setClassMetamethods(subclass)
    _setDefaultInitializeMethod(subclass, self)
    self.subclasses[subclass] = true
    self:subclassed(subclass)

    return subclass
end

function Object.static:subclassed(other) end

function Object.static:isSubclassOf(other)
    return type(other)                   == 'table' and
    type(self)                    == 'table' and
    type(self.super)              == 'table' and
    ( self.super == other or
    type(self.super.isSubclassOf) == 'function' and
    self.super:isSubclassOf(other)
    )
end

function Object.static:include( ... )
    assert(type(self) == 'table', "Make sure you that you are using 'Class:include' instead of 'Class.include'")
    for _,mixin in ipairs({...}) do _includeMixin(self, mixin) end
    return self
end

function Object.static:includes(mixin)
    return type(mixin)          == 'table' and
    type(self)           == 'table' and
    type(self.__mixins)  == 'table' and
    ( self.__mixins[mixin] or
    type(self.super)           == 'table' and
    type(self.super.includes)  == 'function' and
    self.super:includes(mixin)
    )
end

function Object:initialize() end

function Object:__tostring() return "instance of " .. tostring(self.class) end

function Object:isInstanceOf(aClass)
    return type(self)                == 'table' and
    type(self.class)          == 'table' and
    type(aClass)              == 'table' and
    ( aClass == self.class or
    type(aClass.isSubclassOf) == 'function' and
    self.class:isSubclassOf(aClass)
    )
end



function middleclass.class(name, super, ...)
    super = super or Object
    return super:subclass(name, ...)
end

middleclass.Object = Object

setmetatable(middleclass, { __call = function(_, ...) return middleclass.class(...) end })

function table.firstElement(list)
    local _, value = next(list)
    return value
end

Engine = middleclass("Engine")

function Engine:initialize()
    self.entities = {}
    self.rootEntity = Entity()
    self.singleRequirements = {}
    self.allRequirements = {}
    self.entityLists = {}
    self.eventManager = EventManager()

    self.systems = {}
    self.systemRegistry = {}
    self.systems["update"] = {}
    self.systems["draw"] = {}

    self.eventManager:addListener("ComponentRemoved", self, self.componentRemoved)
    self.eventManager:addListener("ComponentAdded", self, self.componentAdded)
end

function Engine:addEntity(entity)
    -- Setting engine eventManager as eventManager for entity
    entity.eventManager = self.eventManager
    -- Getting the next free ID or insert into table
    local newId = #self.entities + 1
    entity.id = newId
    self.entities[entity.id] = entity

    -- If a rootEntity entity is defined and the entity doesn't have a parent yet, the rootEntity entity becomes the entity's parent
    if entity.parent == nil then
        entity:setParent(self.rootEntity)
    end
    entity:registerAsChild()

    for _, component in pairs(entity.components) do
        local name = component.class.name
        -- Adding Entity to specific Entitylist
        if not self.entityLists[name] then self.entityLists[name] = {} end
        self.entityLists[name][entity.id] = entity

        -- Adding Entity to System if all requirements are granted
        if self.singleRequirements[name] then
            for _, system in pairs(self.singleRequirements[name]) do
                self:checkRequirements(entity, system)
            end
        end
    end
end

function Engine:removeEntity(entity, removeChildren, newParent)
    -- Removing the Entity from all Systems and engine
    for _, component in pairs(entity.components) do
        local name = component.class.name
        if self.singleRequirements[name] then
            for _, system in pairs(self.singleRequirements[name]) do
                system:removeEntity(entity)
            end
        end
    end
    -- Deleting the Entity from the specific entity lists
    for _, component in pairs(entity.components) do
        self.entityLists[component.class.name][entity.id] = nil
    end
    if self.entities[entity.id] then
        -- If removeChild is defined, all children become deleted recursively
        if removeChildren then
            for _, child in pairs(entity.children) do
                self:removeEntity(child, true)
            end
        else
            -- If a new Parent is defined, this Entity will be set as the new Parent
            for _, child in pairs(entity.children) do
                if newParent then
                    child:setParent(newParent)
                else
                    child:setParent(self.rootEntity)
                end
                -- Registering as child
                entity:registerAsChild()
            end
        end
        -- Removing Reference to entity from parent
        for _, _ in pairs(entity.parent.children) do
            entity.parent.children[entity.id] = nil
        end
        -- Setting status of entity to dead. This is for other systems, which still got a hard reference on this
        self.entities[entity.id].alive = false
        -- Removing entity from engine
        self.entities[entity.id] = nil
    else
        if lovetoyDebug then
            print("Trying to remove non existent entity from engine.")
            print("Entity id: " .. entity.id)
            print("Entity's components:")
            for index, component in pairs(entity.components) do
                print(index, component)
            end
        end
    end
end

function Engine:addSystem(system, typ)
    local name = system.class.name
    -- Check if system has both function without specified type
    if system.draw and system.update and not typ then
        if lovetoyDebug then
            print("Lovetoys: Trying to add " .. name .. ", which has an update and a draw function, without specifying typ. Aborting")
        end
        return
    end
    -- Adding System to engine system reference table
    if not (self.systemRegistry[name]) then
        self:registerSystem(system)
        -- This triggers if the system doesn't have update and draw and it's already existing.
        elseif not (system.update and system.draw) then
            if self.systemRegistry[name] then
                if lovetoyDebug then
                    print("Lovetoys: " .. name .. " already exists. Aborting")
                end
                return
            end
        end

        -- Adding System to draw table
        if system.draw and (not typ or typ == "draw") then
            for _, registeredSystem in pairs(self.systems["draw"]) do
                if registeredSystem.class.name == name then
                    if lovetoyDebug then
                        print("Lovetoys: " .. name .. " already exists. Aborting")
                    end
                    return
                end
            end
            table.insert(self.systems["draw"], system)
            -- Adding System to update table
            elseif system.update and (not typ or typ == "update") then
                for _, registeredSystem in pairs(self.systems["update"]) do
                    if registeredSystem.class.name == name then
                        if lovetoyDebug then
                            print("Lovetoys: " .. name .. " already exists. Aborting")
                        end
                        return
                    end
                end
                table.insert(self.systems["update"], system)
            end

            -- Checks if some of the already existing entities match the required components.
            for _, entity in pairs(self.entities) do
                self:checkRequirements(entity, system)
            end
            return system
        end

        function Engine:registerSystem(system)
            local name = system.class.name
            self.systemRegistry[name] = system
            -- Registering in case system:requires returns a table of strings
            if system:requires()[1] and type(system:requires()[1]) == "string" then
                for index, req in pairs(system:requires()) do
                    -- Registering at singleRequirements
                    if index == 1 then
                        self.singleRequirements[req] = self.singleRequirements[req] or {}
                        table.insert(self.singleRequirements[req], system)
                    end
                    -- Registering at allRequirements
                    self.allRequirements[req] = self.allRequirements[req] or {}
                    table.insert(self.allRequirements[req], system)
                end
            end

            -- Registering in case its a table of tables which contain strings
            if table.firstElement(system:requires()) and type(table.firstElement(system:requires())) == "table" then
                for index, componentList in pairs(system:requires()) do
                    -- Registering at singleRequirements
                    local component = componentList[1]
                    self.singleRequirements[component] = self.singleRequirements[component] or {}
                    table.insert(self.singleRequirements[component], system)

                    -- Registering at allRequirements
                    for _, req in pairs(componentList) do
                        self.allRequirements[req] = self.allRequirements[req] or {}
                        -- Check if this List already contains the System
                        local contained = false
                        for _, registeredSystem in pairs(self.allRequirements[req]) do
                            if registeredSystem == system then
                                contained = true
                                break
                            end
                        end
                        if not contained then
                            table.insert(self.allRequirements[req], system)
                        end
                    end
                    system.targets[index] = {}
                end
            end
        end

        function Engine:stopSystem(name)
            if self.systemRegistry[name] then
                self.systemRegistry[name].active = false
                elseif lovetoyDebug then
                    print("Lovetoys: Trying to stop unexisting System: " .. name)
                end
            end

            function Engine:startSystem(name)
                if self.systemRegistry[name] then
                    self.systemRegistry[name].active = true
                    elseif lovetoyDebug then
                        print("Lovetoys: Trying to start unexisting System: " .. name)
                    end
                end

                function Engine:toggleSystem(name)
                    if self.systemRegistry[name] then
                        self.systemRegistry[name].active = not self.systemRegistry[name].active
                        elseif lovetoyDebug then
                            print("Lovetoys: Trying to toggle unexisting System: " .. name)
                        end
                    end

                    function Engine:update(dt)
                        for _, system in ipairs(self.systems["update"]) do
                            if system.active then
                                system:update(dt)
                            end
                        end
                    end

                    function Engine:draw()
                        for _, system in ipairs(self.systems["draw"]) do
                            if system.active then
                                system:draw()
                            end
                        end
                    end

                    function Engine:componentRemoved(event)
                        local entity = event.entity
                        local component = event.component

                        -- Removing Entity from Entitylists
                        self.entityLists[component][entity.id] = nil

                        -- Removing Entity from old systems
                        if self.allRequirements[component] then
                            for _, system in pairs(self.allRequirements[component]) do
                                system:removeEntity(entity, component)
                            end
                        end
                    end

                    function Engine:componentAdded(event)
                        local entity = event.entity
                        local component = event.component

                        -- Adding the Entity to Entitylist
                        if not self.entityLists[component] then self.entityLists[component] = {} end
                        self.entityLists[component][entity.id] = entity

                        -- Adding the Entity to the requiring systems
                        if self.allRequirements[component] then
                            for _, system in pairs(self.allRequirements[component]) do
                                self:checkRequirements(entity, system)
                            end
                        end
                    end

                    function Engine:getRootEntity()
                        if self.rootEntity ~= nil then
                            return self.rootEntity
                        end
                    end

                    -- Returns an Entitylist for a specific component. If the Entitylist doesn't exist yet it'll be created and returned.
                    function Engine:getEntitiesWithComponent(component)
                        if not self.entityLists[component] then self.entityLists[component] = {} end
                        return self.entityLists[component]
                    end

                    function Engine:checkRequirements(entity, system) -- luacheck: ignore self
                        local meetsrequirements = true
                        local category = nil
                        for index, req in pairs(system:requires()) do
                            if type(req) == "string" then
                                if not entity.components[req] then
                                    meetsrequirements = false
                                    break
                                end
                                elseif type(req) == "table" then
                                    meetsrequirements = true
                                    for _, req2 in pairs(req) do
                                        if not entity.components[req2] then
                                            meetsrequirements = false
                                            break
                                        end
                                    end
                                    if meetsrequirements == true then
                                        category = index
                                        system:addEntity(entity, category)
                                    end
                                end
                            end
                            if meetsrequirements == true and category == nil then
                                system:addEntity(entity)
                            end
                        end
Entity = middleclass("Entity")

function Entity:initialize(parent, name)
    self.components = {}
    self.eventManager = nil
    self.alive = false
    if parent then
        self:setParent(parent)
    else
        parent = nil
    end
    self.name = name
    self.children = {}
end

-- Sets the entities component of this type to the given component.
-- An entity can only have one Component of each type.
function Entity:add(component)
    local name = component.class.name
    if self.components[name] then
        if lovetoyDebug then
            print("Trying to add Component '" .. name .. "', but it's already existing. Please use Entity:set to overwrite a component in an entity.")
        end
    else
        self.components[name] = component
        if self.eventManager then
            self.eventManager:fireEvent(ComponentAdded(self, name))
        end
    end
end

function Entity:set(component)
    local name = component.class.name
    if self.components[name] == nil then
        self:add(component)
    else
        self.components[name] = component
    end
end

function Entity:addMultiple(componentList)
    for _, component in  pairs(componentList) do
        self:add(component)
    end
end

-- Removes a component from the entity.
function Entity:remove(name)
    if self.components[name] then
        self.components[name] = nil
    else
        if lovetoyDebug then
            print("Trying to remove unexisting component " .. name .. " from Entity. Please fix this")
        end
    end
    if self.eventManager then
        self.eventManager:fireEvent(ComponentRemoved(self, name))
    end
end

function Entity:setParent(parent)
    if self.parent then self.parent.children[self.id] = nil end
    self.parent = parent
    self:registerAsChild()
end

function Entity:getParent()
    return self.parent
end

function Entity:registerAsChild()
    if self.id then self.parent.children[self.id] = self end
end

function Entity:get(name)
    return self.components[name]
end

function Entity:has(name)
    return not not self.components[name]
end

function Entity:getComponents()
    return self.components
end

-- Collection of utilities for handling Components
Component = {}

Component.all = {}

-- Create a Component class with the specified name and fields
-- which will automatically get a constructor accepting the fields as arguments
function Component.create(name, fields, defaults)
    local component = middleclass(name)

    if fields then
        defaults = defaults or {}
        component.initialize = function(self, ...)
            local args = {...}
            for index, field in ipairs(fields) do
                self[field] = args[index] or defaults[field]
            end
        end
    end

    Component.register(component)

    return component
end

-- Register a Component to make it available to Component.load
function Component.register(componentClass)
    Component.all[componentClass.name] = componentClass
end

-- Load multiple components and populate the calling functions namespace with them
-- This should only be called from the top level of a file!
function Component.load(names)
    local components = {}

    for _, name in pairs(names) do
        components[#components+1] = Component.all[name]
    end
    return unpack(components)
end

System = middleclass("System")

function System:initialize()
    -- Liste aller Entities, die die RequiredComponents dieses Systems haben
    self.targets = {}
    self.active = true
end

function System:requires() return {} end

function System:addEntity(entity, category)
    -- If there are multiple requirement lists, the added entities will
    -- be added to their respetive list.
    if category then
        if not self.targets[category] then
            self.targets[category] = {}
        end
        self.targets[category][entity.id] = entity
    else
        -- Otherwise they'll be added to the normal self.targets list
        self.targets[entity.id] = entity
    end

    if self.onAddEntity then self:onAddEntity(entity) end
end

function System:removeEntity(entity, component)
    if table.firstElement(self.targets) then
        if table.firstElement(self.targets).class then
            self.targets[entity.id] = nil
        else
            -- Removing entities from their respective category target list.
            for index, _ in pairs(self.targets) do
                if component then
                    for _, req in pairs(self:requires()[index]) do
                        if req == component then
                            self.targets[index][entity.id] = nil
                            break
                        end
                    end
                else
                    self.targets[index][entity.id] = nil
                end
            end
        end
    end
end

function System:pickRequiredComponents(entity)
    local components = {}
    local requirements = self:requires()

    if not requirements[1] then
    elseif type(requirements[1]) == "string" then
        for _, componentName in pairs(requirements) do
            table.insert(components, entity:get(componentName))
        end
    elseif type(requirements[1]) == "table" then
        if lovetoyDebug then
            print("Error: :pickRequiredComponents() is not supported for systems with multiple component constellations")
        end
    end
    return unpack(components)
end
EventManager = middleclass("EventManager")

function EventManager:initialize()
    self.eventListeners = {}
end

-- Adding an eventlistener to a specific event
function EventManager:addListener(eventName, listener, listenerFunction)
    -- If there's no list for this event, we create a new one
    if not self.eventListeners[eventName] then
        self.eventListeners[eventName] = {}
    end

    for _, registeredListener in pairs(self.eventListeners[eventName]) do
        if registeredListener[1].class == listener.class then
            if lovetoyDebug then
                print("EventListener already existing. Aborting")
            end
            return
        end
    end
    if type(listenerFunction) == 'function' then
        table.insert(self.eventListeners[eventName], {listener, listenerFunction})
    else
        if lovetoyDebug then
            print('Eventmanager: Second parameter has to be a function! Pls check ' .. listener.class.name)
        end
    end
end

-- Removing an eventlistener from an event
function EventManager:removeListener(eventName, listener)
    if self.eventListeners[eventName] then
        for key, registeredListener in pairs(self.eventListeners[eventName]) do
            if registeredListener[1].class.name == listener then
                table.remove(self.eventListeners[eventName], key)
                return
            end
        end
        if lovetoyDebug then
            print("Listener to be deleted is not existing.")
        end
    end
end

-- Firing an event. All registered listener will react to this event
function EventManager:fireEvent(event)
    local name = event.class.name
    if self.eventListeners[name] then
        for _,listener in pairs(self.eventListeners[name]) do
            listener[2](listener[1], event)
        end
    end
end

ComponentAdded = middleclass("ComponentAdded")

function ComponentAdded:initialize(entity, component)
    self.entity = entity
    self.component = component
end

ComponentRemoved = middleclass("ComponentRemoved")

function ComponentRemoved:initialize(entity, component)
    self.entity = entity
    self.component = component
end

