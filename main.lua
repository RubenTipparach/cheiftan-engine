-- Simplified version to verify 3D math works
local mat4 = require("mat4")
local vec3 = require("vec3")
local mesh = require("mesh")
local profiler = require("profiler")

local cube
local camera = {
    pos = vec3.new(0, 0, -5),
    rotation = {x = 0, y = 0, z = 0}
}
local time = 0
local texture

-- Array of cube instances
local cubes = {}

-- Rendering constants
local RENDER_WIDTH = 960
local RENDER_HEIGHT = 540
local NUM_CUBES = 5000  -- Change this to spawn more/fewer cubes
local renderCanvas
local batchMesh  -- Reusable mesh for batching triangles

-- Preallocated arrays for sorting (avoid GC)
local sortedCubes = {}
local allTriangles = {}
local vertexData = {}

-- Preallocated buffers for matrix operations (avoid 36k+ allocations per frame!)
local tempVec = {0, 0, 0, 1}
local tempResult1 = {0, 0, 0, 0}
local tempResult2 = {0, 0, 0, 0}
local tempResult3 = {0, 0, 0, 0}

-- Software rendering resources
local softwareImageData
local softwareZBuffer
local textureData

-- GIF recording
local GIF = require("gif")
local recording = false
local recordedFrames = nil
local frameCount = 0
local recordStartTime = 0
local MAX_RECORD_TIME = 10 -- Auto-cancel after 10 seconds
local lastFrameTime = 0
local FRAME_INTERVAL = 1 / 30 -- 30 fps

-- Notification system
local notification = ""
local notificationTime = 0
local NOTIFICATION_DURATION = 0.5

-- Coroutine for saving
local saveCoroutine = nil
local isSaving = false

-- Menu and rendering mode
local gameState = "menu"  -- "menu" or "playing"
local renderMode = "hardware"  -- "software" or "hardware"
local menuSelection = 1  -- 1 = hardware, 2 = software

function love.load()
    love.window.setTitle("Simple Wireframe 3D Cube")

    -- Disable antialiasing
    love.graphics.setLineStyle("rough")
    love.graphics.setDefaultFilter("nearest", "nearest")

    -- Create canvas for rendering at fixed resolution
    renderCanvas = love.graphics.newCanvas(RENDER_WIDTH, RENDER_HEIGHT)
    renderCanvas:setFilter("nearest", "nearest")

    -- Load texture as both Image and ImageData
    textureData = love.image.newImageData("checkered_placeholder.png")
    texture = love.graphics.newImage(textureData)
    texture:setFilter("nearest", "nearest")

    cube = mesh.createCube()
    print("Cube loaded with " .. #cube.triangles .. " triangles")
    print("Texture loaded: " .. texture:getWidth() .. "x" .. texture:getHeight())

    -- Generate cubes with random positions and rotations
    math.randomseed(os.time())
    for i = 1, NUM_CUBES do
        table.insert(cubes, {
            x = math.random(-50, 50),
            y = math.random(-50, 50),
            z = math.random(0, 100), -- In front of camera
            rotX = math.random() * math.pi * 2,
            rotY = math.random() * math.pi * 2,
            rotZ = math.random() * math.pi * 2,
            rotSpeedX = (math.random() - 0.5) * 2,
            rotSpeedY = (math.random() - 0.5) * 2,
            rotSpeedZ = (math.random() - 0.5) * 2
        })
    end
    print("Generated " .. #cubes .. " cubes")

    -- Create a large batch mesh (preallocate for max triangles)
    local maxTriangles = NUM_CUBES * 12 * 3  -- cubes * tris per cube * verts per tri
    batchMesh = love.graphics.newMesh(maxTriangles, "triangles", "stream")
    batchMesh:setTexture(texture)

    -- Initialize software rendering resources
    softwareImageData = love.image.newImageData(RENDER_WIDTH, RENDER_HEIGHT)
    softwareZBuffer = {}
    for i = 1, RENDER_WIDTH * RENDER_HEIGHT do
        softwareZBuffer[i] = math.huge
    end
end

-- Software rendering helpers
local function setPixel(x, y, z, r, g, b)
    if x < 0 or x >= RENDER_WIDTH or y < 0 or y >= RENDER_HEIGHT then
        return
    end

    local index = math.floor(y) * RENDER_WIDTH + math.floor(x) + 1

    if z < softwareZBuffer[index] then
        softwareZBuffer[index] = z
        softwareImageData:setPixel(math.floor(x), math.floor(y), r, g, b, 1)
    end
end

local function barycentric(ax, ay, bx, by, cx, cy, px, py)
    local v0x = cx - ax
    local v0y = cy - ay
    local v1x = bx - ax
    local v1y = by - ay
    local v2x = px - ax
    local v2y = py - ay

    local dot00 = v0x * v0x + v0y * v0y
    local dot01 = v0x * v1x + v0y * v1y
    local dot02 = v0x * v2x + v0y * v2y
    local dot11 = v1x * v1x + v1y * v1y
    local dot12 = v1x * v2x + v1y * v2y

    local invDenom = 1 / (dot00 * dot11 - dot01 * dot01)
    local u = (dot11 * dot02 - dot01 * dot12) * invDenom
    local v = (dot00 * dot12 - dot01 * dot02) * invDenom

    return u, v, 1 - u - v
end

local function drawTriangleSoftware(v1, v2, v3)
    local minX = math.max(0, math.floor(math.min(v1[1], v2[1], v3[1])))
    local maxX = math.min(RENDER_WIDTH - 1, math.ceil(math.max(v1[1], v2[1], v3[1])))
    local minY = math.max(0, math.floor(math.min(v1[2], v2[2], v3[2])))
    local maxY = math.min(RENDER_HEIGHT - 1, math.ceil(math.max(v1[2], v2[2], v3[2])))

    local texWidth = textureData:getWidth()
    local texHeight = textureData:getHeight()

    for y = minY, maxY do
        for x = minX, maxX do
            local w1, w2, w3 = barycentric(v1[1], v1[2], v2[1], v2[2], v3[1], v3[2], x + 0.5, y + 0.5)

            if w1 >= 0 and w2 >= 0 and w3 >= 0 then
                -- Interpolate depth
                local z = w1 * v1[9] + w2 * v2[9] + w3 * v3[9]

                -- Perspective-correct interpolation
                local w = w1 * v1[10] + w2 * v2[10] + w3 * v3[10]
                if w > 0 then
                    local u = (w1 * v1[3] * v1[10] + w2 * v2[3] * v2[10] + w3 * v3[3] * v3[10]) / w
                    local v = (w1 * v1[4] * v1[10] + w2 * v2[4] * v2[10] + w3 * v3[4] * v3[10]) / w

                    local texX = math.floor((u % 1) * texWidth) % texWidth
                    local texY = math.floor((v % 1) * texHeight) % texHeight

                    local r, g, b = textureData:getPixel(texX, texY)
                    setPixel(x, y, z, r, g, b)
                end
            end
        end
    end
end

local function startSave()
    isSaving = true
    notification = "Saving GIF..."
    notificationTime = 999 -- Keep notification visible during save
    print("Saving GIF with " .. frameCount .. " frames...")

    -- Generate timestamp filename
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local filename = string.format("recording_%s.gif", timestamp)

    saveCoroutine = coroutine.create(function()
        local success, err = recordedFrames:save(filename)
        if success then
            notification = "Recording saved!"
            notificationTime = NOTIFICATION_DURATION
            local saveDir = love.filesystem.getSaveDirectory()
            print("GIF saved as " .. filename .. " in: " .. saveDir)
            love.system.openURL("file://" .. saveDir)
        else
            notification = "Error saving GIF!"
            notificationTime = NOTIFICATION_DURATION
            print("Error saving GIF: " .. tostring(err))
        end
        recordedFrames = nil
        isSaving = false
        saveCoroutine = nil
    end)
end

function love.update(dt)
    time = time + dt

    -- Update cube rotations
    for _, c in ipairs(cubes) do
        c.rotX = c.rotX + c.rotSpeedX * dt
        c.rotY = c.rotY + c.rotSpeedY * dt
        c.rotZ = c.rotZ + c.rotSpeedZ * dt
    end

    -- Update notification timer
    if notificationTime > 0 and not isSaving then
        notificationTime = notificationTime - dt
        if notificationTime <= 0 then
            notification = ""
        end
    end

    -- Resume save coroutine if it exists
    if saveCoroutine then
        local status = coroutine.status(saveCoroutine)
        if status ~= "dead" then
            coroutine.resume(saveCoroutine)
        end
    end

    -- Auto-cancel recording after 10 seconds
    if recording and (love.timer.getTime() - recordStartTime) >= MAX_RECORD_TIME then
        recording = false
        print("Recording auto-stopped after " .. MAX_RECORD_TIME .. " seconds.")
        startSave()
    end

    -- Camera rotation controls
    if love.keyboard.isDown("left") then camera.rotation.y = camera.rotation.y - dt * 2 end
    if love.keyboard.isDown("right") then camera.rotation.y = camera.rotation.y + dt * 2 end
    if love.keyboard.isDown("up") then camera.rotation.x = camera.rotation.x - dt * 2 end
    if love.keyboard.isDown("down") then camera.rotation.x = camera.rotation.x + dt * 2 end

    -- Camera movement (relative to camera orientation)
    local moveSpeed = 3
    local moveX, moveY, moveZ = 0, 0, 0

    -- Calculate forward and right vectors based on camera rotation
    local yaw = camera.rotation.y
    local pitch = camera.rotation.x

    -- Forward direction (affected by yaw and pitch)
    local forwardX = math.sin(yaw) * math.cos(pitch)
    local forwardY = -math.sin(pitch)
    local forwardZ = math.cos(yaw) * math.cos(pitch)

    -- Right direction (perpendicular to forward, only affected by yaw)
    local rightX = math.cos(yaw)
    local rightY = 0
    local rightZ = -math.sin(yaw)

    -- Apply movement
    if love.keyboard.isDown("w") then
        moveX = moveX + forwardX * moveSpeed * dt
        moveY = moveY + forwardY * moveSpeed * dt
        moveZ = moveZ + forwardZ * moveSpeed * dt
    end
    if love.keyboard.isDown("s") then
        moveX = moveX - forwardX * moveSpeed * dt
        moveY = moveY - forwardY * moveSpeed * dt
        moveZ = moveZ - forwardZ * moveSpeed * dt
    end
    if love.keyboard.isDown("a") then
        moveX = moveX - rightX * moveSpeed * dt
        moveY = moveY - rightY * moveSpeed * dt
        moveZ = moveZ - rightZ * moveSpeed * dt
    end
    if love.keyboard.isDown("d") then
        moveX = moveX + rightX * moveSpeed * dt
        moveY = moveY + rightY * moveSpeed * dt
        moveZ = moveZ + rightZ * moveSpeed * dt
    end

    camera.pos.x = camera.pos.x + moveX
    camera.pos.y = camera.pos.y + moveY
    camera.pos.z = camera.pos.z + moveZ
end

function love.keypressed(key)
    -- Menu controls
    if gameState == "menu" then
        if key == "up" then
            menuSelection = menuSelection - 1
            if menuSelection < 1 then menuSelection = 2 end
        elseif key == "down" then
            menuSelection = menuSelection + 1
            if menuSelection > 2 then menuSelection = 1 end
        elseif key == "return" or key == "space" then
            -- Start game with selected mode
            renderMode = (menuSelection == 1) and "hardware" or "software"
            gameState = "playing"
        end
        return
    end

    -- In-game controls
    if key == "escape" then
        gameState = "menu"
        return
    end

    if key == "f8" then
        if not recording and not isSaving then
            -- Start recording
            recording = true
            recordedFrames = GIF.new(RENDER_WIDTH * 2, RENDER_HEIGHT * 2, 3) -- 2x resolution, ~30fps
            frameCount = 0
            recordStartTime = love.timer.getTime()
            lastFrameTime = 0
            notification = "Recording started"
            notificationTime = NOTIFICATION_DURATION
            print("Recording started...")
        elseif recording then
            -- Stop recording and save
            recording = false
            print("Recording stopped.")
            startSave()
        end
    end

    if key == "f9" then
        -- Open save directory
        love.system.openURL("file://" .. love.filesystem.getSaveDirectory())
        print("Save directory: " .. love.filesystem.getSaveDirectory())
    end
end

function love.draw()
    if gameState == "menu" then
        -- Draw menu
        love.graphics.setCanvas()
        love.graphics.clear(0, 0, 0)
        love.graphics.setColor(1, 1, 1)

        local windowWidth, windowHeight = love.graphics.getDimensions()
        local centerX = windowWidth / 2
        local centerY = windowHeight / 2

        -- Title
        love.graphics.printf("SELECT RENDERING MODE", 0, centerY - 100, windowWidth, "center")

        -- Menu options
        local option1Color = menuSelection == 1 and {1, 1, 0} or {1, 1, 1}
        local option2Color = menuSelection == 2 and {1, 1, 0} or {1, 1, 1}

        love.graphics.setColor(option1Color)
        love.graphics.printf("> Hardware Rendering (GPU Depth)", 0, centerY - 20, windowWidth, "center")

        love.graphics.setColor(option2Color)
        love.graphics.printf("> Software Rendering (CPU)", 0, centerY + 20, windowWidth, "center")

        love.graphics.setColor(1, 1, 1)
        love.graphics.printf("Arrow Keys to Select | Enter/Space to Start", 0, centerY + 80, windowWidth, "center")

        return
    end

    profiler.startFrame()

    -- Hardware mode renders directly to screen for depth buffer support
    -- Software mode uses canvas
    if renderMode == "software" then
        love.graphics.setCanvas(renderCanvas)
    else
        love.graphics.setCanvas()
    end
    love.graphics.clear(0, 0, 0)
    love.graphics.setColor(1, 1, 1)

    -- Use window dimensions for hardware mode (direct rendering), canvas size for software
    local width, height
    if renderMode == "hardware" then
        width, height = love.graphics.getDimensions()
    else
        width, height = RENDER_WIDTH, RENDER_HEIGHT
    end

    profiler.start("matrices")
    -- View and projection matrices
    local viewMatrix = mat4.identity()
    viewMatrix = mat4.multiply(viewMatrix, mat4.rotationX(camera.rotation.x))
    viewMatrix = mat4.multiply(viewMatrix, mat4.rotationY(camera.rotation.y))
    viewMatrix = mat4.multiply(viewMatrix, mat4.translation(camera.pos.x, camera.pos.y, camera.pos.z))

    local projectionMatrix = mat4.perspective(70, width/height, 0.1, 100)

    -- Pre-combine view-projection matrix (same for all cubes)
    local vpMatrix = mat4.multiply(projectionMatrix, viewMatrix)
    profiler.stop("matrices")

    profiler.start("cube_sort")
    -- Step 1: Calculate depth for each cube and reuse sortedCubes table
    local numCubes = #cubes
    for i = 1, numCubes do
        local cubeInstance = cubes[i]
        -- Calculate distance from camera
        local dx = cubeInstance.x - camera.pos.x
        local dy = cubeInstance.y - camera.pos.y
        local dz = cubeInstance.z - camera.pos.z
        local depth = dx*dx + dy*dy + dz*dz

        -- Reuse existing entries
        local entry = sortedCubes[i]
        if not entry then
            entry = {}
            sortedCubes[i] = entry
        end
        entry.cube = cubeInstance
        entry.depth = depth
    end

    -- Clear extra entries
    for i = numCubes + 1, #sortedCubes do
        sortedCubes[i] = nil
    end

    -- Sort cubes by depth (farthest first)
    table.sort(sortedCubes, function(a, b) return a.depth > b.depth end)
    profiler.stop("cube_sort")

    profiler.start("cull_project")
    -- Step 2: Collect triangles (reuse allTriangles table)
    local triCount = 0

    -- Helper function for frustum checks (defined once)
    local function inFrustum(x, y, z, w)
        return w > 0 and x >= -w and x <= w and y >= -w and y <= w and z >= 0 and z <= w
    end

    for _, sortedCube in ipairs(sortedCubes) do
        local cubeInstance = sortedCube.cube

        profiler.start("  model_build")
        -- Build model matrix with fewer operations
        local modelMatrix = mat4.translation(cubeInstance.x, cubeInstance.y, cubeInstance.z)
        modelMatrix = mat4.multiply(modelMatrix, mat4.rotationY(cubeInstance.rotY))
        modelMatrix = mat4.multiply(modelMatrix, mat4.rotationX(cubeInstance.rotX))
        modelMatrix = mat4.multiply(modelMatrix, mat4.rotationZ(cubeInstance.rotZ))
        profiler.stop("  model_build")

        profiler.start("  mvp_multiply")
        -- Use pre-combined VP matrix (saves one matrix multiply per cube)
        local mvpMatrix = mat4.multiply(vpMatrix, modelMatrix)
        profiler.stop("  mvp_multiply")

        profiler.start("  cube_frustum")
        -- Frustum cull entire cube: transform center and check with radius margin
        tempVec[1], tempVec[2], tempVec[3] = 0, 0, 0  -- Cube center in local space
        local center = mat4.multiplyVec4(mvpMatrix, tempVec)
        local cx, cy, cz, cw = center[1], center[2], center[3], center[4]

        -- Check if cube center is in frustum with margin (cube has size ~2, so radius ~1.732)
        local margin = 2.0  -- Conservative margin for cube diagonal
        local cubeVisible = cw > 0 and
                           cx >= -cw - margin and cx <= cw + margin and
                           cy >= -cw - margin and cy <= cw + margin and
                           cz >= -margin and cz <= cw + margin
        profiler.stop("  cube_frustum")

        if not cubeVisible then
            -- Skip all triangles for this cube
            goto continue_cube
        end

        -- Process each triangle of this cube
        for _, tri in ipairs(cube.triangles) do
            local v1 = cube.vertices[tri[1]]
            local v2 = cube.vertices[tri[2]]
            local v3 = cube.vertices[tri[3]]

            if renderMode == "hardware" then
                profiler.start("  vertex_xform")
                -- Hardware mode: Just transform and add all triangles (GPU handles culling/depth)
                tempVec[1], tempVec[2], tempVec[3] = v1.pos[1], v1.pos[2], v1.pos[3]
                local p1 = mat4.multiplyVec4(mvpMatrix, tempVec)
                local p1x, p1y, p1z, p1w = p1[1], p1[2], p1[3], p1[4]

                tempVec[1], tempVec[2], tempVec[3] = v2.pos[1], v2.pos[2], v2.pos[3]
                local p2 = mat4.multiplyVec4(mvpMatrix, tempVec)
                local p2x, p2y, p2z, p2w = p2[1], p2[2], p2[3], p2[4]

                tempVec[1], tempVec[2], tempVec[3] = v3.pos[1], v3.pos[2], v3.pos[3]
                local p3 = mat4.multiplyVec4(mvpMatrix, tempVec)
                local p3x, p3y, p3z, p3w = p3[1], p3[2], p3[3], p3[4]

                -- Quick check: only skip if all vertices behind camera
                if p1w > 0 or p2w > 0 or p3w > 0 then
                    local s1x = (p1x / p1w + 1) * width * 0.5
                    local s1y = (1 - p1y / p1w) * height * 0.5
                    local s2x = (p2x / p2w + 1) * width * 0.5
                    local s2y = (1 - p2y / p2w) * height * 0.5
                    local s3x = (p3x / p3w + 1) * width * 0.5
                    local s3y = (1 - p3y / p3w) * height * 0.5

                    triCount = triCount + 1
                    local tri = allTriangles[triCount]
                    if not tri then
                        tri = {vertices = {{}, {}, {}}}
                        allTriangles[triCount] = tri
                    end

                    tri.depth = 0  -- Not used in hardware mode

                    local v1_data = tri.vertices[1]
                    v1_data[1], v1_data[2], v1_data[3], v1_data[4] = s1x, s1y, v1.uv[1], v1.uv[2]
                    v1_data[5], v1_data[6], v1_data[7], v1_data[8] = 1, 1, 1, 1

                    local v2_data = tri.vertices[2]
                    v2_data[1], v2_data[2], v2_data[3], v2_data[4] = s2x, s2y, v2.uv[1], v2.uv[2]
                    v2_data[5], v2_data[6], v2_data[7], v2_data[8] = 1, 1, 1, 1

                    local v3_data = tri.vertices[3]
                    v3_data[1], v3_data[2], v3_data[3], v3_data[4] = s3x, s3y, v3.uv[1], v3.uv[2]
                    v3_data[5], v3_data[6], v3_data[7], v3_data[8] = 1, 1, 1, 1
                end
                profiler.stop("  vertex_xform")
            else
                -- Software mode: Full CPU culling pipeline
                profiler.start("  vertex_xform")
                tempVec[1], tempVec[2], tempVec[3] = v1.pos[1], v1.pos[2], v1.pos[3]
                local p1 = mat4.multiplyVec4(mvpMatrix, tempVec)
                local p1x, p1y, p1z, p1w = p1[1], p1[2], p1[3], p1[4]

                tempVec[1], tempVec[2], tempVec[3] = v2.pos[1], v2.pos[2], v2.pos[3]
                local p2 = mat4.multiplyVec4(mvpMatrix, tempVec)
                local p2x, p2y, p2z, p2w = p2[1], p2[2], p2[3], p2[4]

                tempVec[1], tempVec[2], tempVec[3] = v3.pos[1], v3.pos[2], v3.pos[3]
                local p3 = mat4.multiplyVec4(mvpMatrix, tempVec)
                local p3x, p3y, p3z, p3w = p3[1], p3[2], p3[3], p3[4]
                profiler.stop("  vertex_xform")

                profiler.start("  tri_frustum")
                local v1Inside = inFrustum(p1x, p1y, p1z, p1w)
                local v2Inside = inFrustum(p2x, p2y, p2z, p2w)
                local v3Inside = inFrustum(p3x, p3y, p3z, p3w)

                if v1Inside or v2Inside or v3Inside then
                    profiler.stop("  tri_frustum")

                    profiler.start("  backface_cull")
                    local s1x = (p1x / p1w + 1) * width * 0.5
                    local s1y = (1 - p1y / p1w) * height * 0.5
                    local s2x = (p2x / p2w + 1) * width * 0.5
                    local s2y = (1 - p2y / p2w) * height * 0.5
                    local s3x = (p3x / p3w + 1) * width * 0.5
                    local s3y = (1 - p3y / p3w) * height * 0.5

                    local edge1x = s2x - s1x
                    local edge1y = s2y - s1y
                    local edge2x = s3x - s1x
                    local edge2y = s3y - s1y
                    local cross = edge1x * edge2y - edge1y * edge2x

                    if cross < 0 then
                        local avgDepth = (p1z / p1w + p2z / p2w + p3z / p3w) / 3

                        triCount = triCount + 1
                        local tri = allTriangles[triCount]
                        if not tri then
                            tri = {vertices = {{}, {}, {}}}
                            allTriangles[triCount] = tri
                        end

                        tri.depth = avgDepth

                        local v1_data = tri.vertices[1]
                        v1_data[1], v1_data[2], v1_data[3], v1_data[4] = s1x, s1y, v1.uv[1], v1.uv[2]
                        v1_data[5], v1_data[6], v1_data[7], v1_data[8] = 1, 1, 1, 1
                        v1_data[9], v1_data[10] = p1z / p1w, 1 / p1w

                        local v2_data = tri.vertices[2]
                        v2_data[1], v2_data[2], v2_data[3], v2_data[4] = s2x, s2y, v2.uv[1], v2.uv[2]
                        v2_data[5], v2_data[6], v2_data[7], v2_data[8] = 1, 1, 1, 1
                        v2_data[9], v2_data[10] = p2z / p2w, 1 / p2w

                        local v3_data = tri.vertices[3]
                        v3_data[1], v3_data[2], v3_data[3], v3_data[4] = s3x, s3y, v3.uv[1], v3.uv[2]
                        v3_data[5], v3_data[6], v3_data[7], v3_data[8] = 1, 1, 1, 1
                        v3_data[9], v3_data[10] = p3z / p3w, 1 / p3w
                    end
                    profiler.stop("  backface_cull")
                else
                    profiler.stop("  tri_frustum")
                end
            end
        end

        ::continue_cube::
    end
    profiler.stop("cull_project")

    -- Step 3: Sort triangles (only needed for software mode - hardware uses GPU depth buffer)
    if renderMode == "software" then
        profiler.start("tri_sort")
        -- Clear unused entries first so table.sort only processes what we need
        for i = triCount + 1, #allTriangles do
            allTriangles[i] = nil
        end

        if triCount > 1 then
            table.sort(allTriangles, function(a, b)
                return a.depth > b.depth
            end)
        end
        profiler.stop("tri_sort")
    else
        -- Hardware mode: no sorting, just clear unused entries
        for i = triCount + 1, #allTriangles do
            allTriangles[i] = nil
        end
    end

    profiler.start("rasterize")
    if renderMode == "hardware" then
        -- Hardware rendering: use GPU depth buffer + backface culling (no CPU sorting needed!)
        love.graphics.setDepthMode("less", true)
        love.graphics.setMeshCullMode("back")

        local vertIdx = 0
        for i = 1, triCount do
            local tri = allTriangles[i]
            for j = 1, 3 do
                vertIdx = vertIdx + 1
                vertexData[vertIdx] = tri.vertices[j]
            end
        end

        if vertIdx > 0 then
            batchMesh:setVertices(vertexData, 1, vertIdx)
            batchMesh:setDrawRange(1, vertIdx)
            love.graphics.draw(batchMesh)
        end

        love.graphics.setMeshCullMode("none")
        love.graphics.setDepthMode()
    else
        -- Software rendering: clear buffers and rasterize pixel by pixel
        for i = 1, RENDER_WIDTH * RENDER_HEIGHT do
            softwareZBuffer[i] = math.huge
        end
        softwareImageData:mapPixel(function() return 0, 0, 0, 1 end)

        -- Draw each triangle
        for i = 1, triCount do
            local tri = allTriangles[i]
            drawTriangleSoftware(tri.vertices[1], tri.vertices[2], tri.vertices[3])
        end

        -- Convert to texture and draw
        local img = love.graphics.newImage(softwareImageData)
        img:setFilter("nearest", "nearest")
        love.graphics.draw(img, 0, 0)
    end
    profiler.stop("rasterize")

    local trianglesDrawn = triCount

    love.graphics.print("Mode: " .. (renderMode == "hardware" and "HARDWARE (GPU)" or "SOFTWARE (CPU)"), 10, 10)
    love.graphics.print("Cubes: " .. #cubes, 10, 30)
    love.graphics.print("Triangles: " .. trianglesDrawn, 10, 50)

    -- Draw profiler info
    local blue = {0.4, 0.6, 1.0}
    local y = 70
    y = profiler.draw("matrices", 10, y)
    y = profiler.draw("cube_sort", 10, y)
    y = profiler.draw("cull_project", 10, y)
    y = profiler.draw("  model_build", 10, y, blue)
    y = profiler.draw("  mvp_multiply", 10, y, blue)
    y = profiler.draw("  cube_frustum", 10, y, blue)
    y = profiler.draw("  vertex_xform", 10, y, blue)
    if renderMode == "software" then
        y = profiler.draw("  tri_frustum", 10, y, blue)
        y = profiler.draw("  backface_cull", 10, y, blue)
        y = profiler.draw("tri_sort", 10, y)
    end
    y = profiler.draw("rasterize", 10, y)
    y = y + 5
    profiler.draw("total", 10, y)

    -- Show notification at bottom
    if notification ~= "" then
        local textWidth = love.graphics.getFont():getWidth(notification)
        love.graphics.print(notification, (RENDER_WIDTH - textWidth) / 2, RENDER_HEIGHT - 20)
    end

    -- Capture frame for GIF if recording (at 2x resolution, limited to 30fps)
    if recording then
        local currentTime = love.timer.getTime() - recordStartTime
        if currentTime - lastFrameTime >= FRAME_INTERVAL then
            lastFrameTime = currentTime

            -- Create a 2x resolution canvas
            local captureCanvas = love.graphics.newCanvas(RENDER_WIDTH * 2, RENDER_HEIGHT * 2)
            captureCanvas:setFilter("nearest", "nearest")

            love.graphics.setCanvas(captureCanvas)
            love.graphics.clear(0, 0, 0)
            love.graphics.draw(renderCanvas, 0, 0, 0, 2, 2)
            love.graphics.setCanvas(renderCanvas)

            -- Get image data and add to GIF
            local imageData = captureCanvas:newImageData()
            recordedFrames:addFrame(imageData)
            frameCount = frameCount + 1

            captureCanvas:release()
        end
    end

    -- Software mode: draw canvas to screen with scaling
    -- Hardware mode: already rendered directly to screen
    if renderMode == "software" then
        love.graphics.setCanvas()
        love.graphics.clear(0, 0, 0)

        -- Calculate scale to fit window while maintaining aspect ratio
        local windowWidth, windowHeight = love.graphics.getDimensions()
        local scaleX = windowWidth / RENDER_WIDTH
        local scaleY = windowHeight / RENDER_HEIGHT
        local scale = math.min(scaleX, scaleY)

        -- Center the canvas in the window
        local offsetX = (windowWidth - RENDER_WIDTH * scale) / 2
        local offsetY = (windowHeight - RENDER_HEIGHT * scale) / 2

        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(renderCanvas, offsetX, offsetY, 0, scale, scale)
    end

    profiler.endFrame()
end
