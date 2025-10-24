-- Software Rendered 3D Engine in Love2D
-- Main entry point

local mat4 = require("mat4")
local vec3 = require("vec3")
local renderer = require("renderer")
local mesh = require("mesh")

-- Game state
local cube
local texture
local camera = {
    pos = vec3.new(0, 0, -5),
    rotation = {x = 0, y = 0, z = 0}
}
local time = 0

function love.load()
    love.window.setTitle("Software Rendered 3D Cube")

    -- Load texture
    texture = love.graphics.newImage("checkered_placeholder.png")
    texture:setFilter("nearest", "nearest")
    print("Texture loaded: " .. texture:getWidth() .. "x" .. texture:getHeight())

    -- Create cube mesh
    cube = mesh.createCube()
    print("Cube created with " .. #cube.triangles .. " triangles")

    -- Initialize renderer
    renderer.init(800, 600)
    print("Renderer initialized")
end

function love.update(dt)
    time = time + dt

    -- Camera rotation with arrow keys
    if love.keyboard.isDown("left") then
        camera.rotation.y = camera.rotation.y - dt * 2
    end
    if love.keyboard.isDown("right") then
        camera.rotation.y = camera.rotation.y + dt * 2
    end
    if love.keyboard.isDown("up") then
        camera.rotation.x = camera.rotation.x - dt * 2
    end
    if love.keyboard.isDown("down") then
        camera.rotation.x = camera.rotation.x + dt * 2
    end

    -- Camera movement with WASD
    local moveSpeed = 3
    if love.keyboard.isDown("w") then
        camera.pos.z = camera.pos.z + moveSpeed * dt
    end
    if love.keyboard.isDown("s") then
        camera.pos.z = camera.pos.z - moveSpeed * dt
    end
    if love.keyboard.isDown("a") then
        camera.pos.x = camera.pos.x - moveSpeed * dt
    end
    if love.keyboard.isDown("d") then
        camera.pos.x = camera.pos.x + moveSpeed * dt
    end
end

function love.draw()
    love.graphics.clear(0.1, 0.1, 0.15)

    -- Create transformation matrices
    local modelMatrix = mat4.identity()
    modelMatrix = mat4.multiply(modelMatrix, mat4.rotationY(time * 0.5))
    modelMatrix = mat4.multiply(modelMatrix, mat4.rotationX(time * 0.3))

    local viewMatrix = mat4.identity()
    viewMatrix = mat4.multiply(viewMatrix, mat4.rotationX(camera.rotation.x))
    viewMatrix = mat4.multiply(viewMatrix, mat4.rotationY(camera.rotation.y))
    viewMatrix = mat4.multiply(viewMatrix, mat4.translation(-camera.pos.x, -camera.pos.y, -camera.pos.z))

    local projectionMatrix = mat4.perspective(70, 800/600, 0.1, 100)

    -- Render the cube
    renderer.renderMesh(cube, modelMatrix, viewMatrix, projectionMatrix, texture)

    -- Draw instructions
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Arrow Keys: Rotate Camera", 10, 10)
    love.graphics.print("WASD: Move Camera", 10, 30)
    love.graphics.print("FPS: " .. love.timer.getFPS(), 10, 50)
end

return {
    load = love.load,
    update = love.update,
    draw = love.draw
}
