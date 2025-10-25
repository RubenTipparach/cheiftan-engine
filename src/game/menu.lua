-- Main Menu Scene Selector
local menu = {}
local scene_manager = require("scene_manager")

local menuItems = {
    {title = "Mesh Test", file = "test_cube_scene.lua"},
    {title = "Stress Test (1000 Cubes)", file = "cubes_scene_dda.lua"},
    {title = "Demo Scene (City)", file = "city_scene.lua"},
    {title = "Fog Scene (Dithered)", file = "fog_scene.lua"},
    {title = "Lighting Test", file = "lighting_test_scene.lua"}
}

local selectedIndex = 1
local windowWidth, windowHeight = 960, 540

function menu.load()
    love.window.setTitle("Chieftan Engine - Scene Selector")
    windowWidth, windowHeight = love.graphics.getDimensions()
end

function menu.update(dt)
end

function menu.draw()
    love.graphics.clear(0.05, 0.05, 0.08)

    -- Title
    love.graphics.setColor(1, 1, 1)
    local centerY = windowHeight / 2
    love.graphics.printf("CHIEFTAN ENGINE", 0, centerY - 100, windowWidth, "center")
    love.graphics.printf("Scene Selector", 0, centerY - 80, windowWidth, "center")

    -- Menu items - compact single line layout
    local startY = centerY - 40
    local itemHeight = 35

    for i, item in ipairs(menuItems) do
        local y = startY + (i - 1) * itemHeight
        local isSelected = (i == selectedIndex)

        -- Selection indicator
        if isSelected then
            love.graphics.setColor(0.4, 0.6, 1.0)
            love.graphics.print(">", 100, y, 0, 1.5, 1.5)
        end

        -- Title
        if isSelected then
            love.graphics.setColor(1, 1, 1)
            love.graphics.print(item.title, 130, y, 0, 1.3, 1.3)
        else
            love.graphics.setColor(0.7, 0.7, 0.7)
            love.graphics.print(item.title, 130, y)
        end
    end

    -- Instructions at bottom
    love.graphics.setColor(0.6, 0.6, 0.6)
    love.graphics.printf("Up/Down: Select  |  Enter: Launch  |  ESC: Quit", 0, windowHeight - 30, windowWidth, "center")
end

function menu.keypressed(key)
    if key == "up" then
        selectedIndex = selectedIndex - 1
        if selectedIndex < 1 then
            selectedIndex = #menuItems
        end
    elseif key == "down" then
        selectedIndex = selectedIndex + 1
        if selectedIndex > #menuItems then
            selectedIndex = 1
        end
    elseif key == "return" or key == "space" then
        menu.launchScene(selectedIndex)
    elseif key == "escape" then
        love.event.quit()
    end
end

function menu.launchScene(index)
    local item = menuItems[index]
    print("Launching scene: " .. item.title)

    -- Map file names to scene names
    local sceneMap = {
        ["test_cube_scene.lua"] = "test_cube",
        ["cubes_scene_dda.lua"] = "cubes_dda",
        ["city_scene.lua"] = "city",
        ["fog_scene.lua"] = "fog",
        ["lighting_test_scene.lua"] = "lighting"
    }

    local sceneName = sceneMap[item.file]
    if sceneName then
        scene_manager.switch(sceneName)
    end
end

function menu.returnToMenu()
    -- Clear loaded modules
    package.loaded.city_scene = nil
    package.loaded.cubes_scene_dda = nil
    package.loaded.test_cube_scene = nil
    package.loaded.fog_scene = nil

    -- Reset to menu
    love.load = menu.load
    love.update = menu.update
    love.draw = menu.draw
    love.keypressed = menu.keypressed
    menu.load()
end

return menu
