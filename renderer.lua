-- Software Renderer

local mat4 = require("mat4")
local vec3 = require("vec3")

local renderer = {}
local width, height
local canvas
local imageData
local zBuffer

function renderer.init(w, h)
    width = w or 480
    height = h or 270
    canvas = love.graphics.newCanvas(width, height)
    imageData = love.image.newImageData(width, height)
    zBuffer = {}
    for i = 1, width * height do
        zBuffer[i] = math.huge
    end
    print("Renderer initialized: " .. width .. "x" .. height)
end

local function clearBuffers()
    -- Clear z-buffer
    for i = 1, width * height do
        zBuffer[i] = math.huge
    end

    -- Clear image data to black
    imageData:mapPixel(function(x, y, r, g, b, a)
        return 0, 0, 0, 1
    end)
end

local function setPixel(x, y, z, r, g, b, a)
    if x < 0 or x >= width or y < 0 or y >= height then
        return
    end

    local index = math.floor(y) * width + math.floor(x) + 1

    if z < zBuffer[index] then
        zBuffer[index] = z
        imageData:setPixel(math.floor(x), math.floor(y), r, g, b, a or 1)
    end
end

-- Barycentric coordinates for point P in triangle ABC
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

local function drawTriangle(v1, v2, v3, texture)
    -- Compute bounding box
    local minX = math.max(0, math.floor(math.min(v1.x, v2.x, v3.x)))
    local maxX = math.min(width - 1, math.ceil(math.max(v1.x, v2.x, v3.x)))
    local minY = math.max(0, math.floor(math.min(v1.y, v2.y, v3.y)))
    local maxY = math.min(height - 1, math.ceil(math.max(v1.y, v2.y, v3.y)))

    local texWidth = texture:getWidth()
    local texHeight = texture:getHeight()
    local texData = texture:getData()

    -- Rasterize
    for y = minY, maxY do
        for x = minX, maxX do
            local w1, w2, w3 = barycentric(v1.x, v1.y, v2.x, v2.y, v3.x, v3.y, x + 0.5, y + 0.5)

            -- Check if point is inside triangle
            if w1 >= 0 and w2 >= 0 and w3 >= 0 then
                -- Interpolate depth
                local z = w1 * v1.z + w2 * v2.z + w3 * v3.z

                -- Perspective-correct interpolation
                local w = w1 * v1.w + w2 * v2.w + w3 * v3.w
                if w > 0 then
                    -- Interpolate UV coordinates
                    local u = (w1 * v1.u * v1.w + w2 * v2.u * v2.w + w3 * v3.u * v3.w) / w
                    local v = (w1 * v1.v * v1.w + w2 * v2.v * v2.w + w3 * v3.v * v3.w) / w

                    -- Sample texture
                    local texX = math.floor((u % 1) * texWidth) % texWidth
                    local texY = math.floor((v % 1) * texHeight) % texHeight

                    local r, g, b, a = texData:getPixel(texX, texY)

                    -- Simple lighting based on distance
                    local brightness = 1.0 / (1.0 + z * 0.1)
                    brightness = math.max(0.3, math.min(1.0, brightness))

                    setPixel(x, y, z, r * brightness, g * brightness, b * brightness, a)
                end
            end
        end
    end
end

function renderer.renderMesh(mesh, modelMatrix, viewMatrix, projectionMatrix, texture)
    clearBuffers()

    -- Combine matrices
    local mvpMatrix = mat4.multiply(mat4.multiply(projectionMatrix, viewMatrix), modelMatrix)

    local trianglesDrawn = 0

    -- Process each triangle
    for _, tri in ipairs(mesh.triangles) do
        local v1 = mesh.vertices[tri[1]]
        local v2 = mesh.vertices[tri[2]]
        local v3 = mesh.vertices[tri[3]]

        -- Transform vertices
        local p1 = mat4.multiplyVec4(mvpMatrix, {v1.pos[1], v1.pos[2], v1.pos[3], 1})
        local p2 = mat4.multiplyVec4(mvpMatrix, {v2.pos[1], v2.pos[2], v2.pos[3], 1})
        local p3 = mat4.multiplyVec4(mvpMatrix, {v3.pos[1], v3.pos[2], v3.pos[3], 1})

        -- Perspective divide
        if p1[4] > 0 and p2[4] > 0 and p3[4] > 0 then
            local screenV1 = {
                x = (p1[1] / p1[4] + 1) * width * 0.5,
                y = (1 - p1[2] / p1[4]) * height * 0.5,
                z = p1[3] / p1[4],
                w = 1 / p1[4],
                u = v1.uv[1],
                v = v1.uv[2]
            }

            local screenV2 = {
                x = (p2[1] / p2[4] + 1) * width * 0.5,
                y = (1 - p2[2] / p2[4]) * height * 0.5,
                z = p2[3] / p2[4],
                w = 1 / p2[4],
                u = v2.uv[1],
                v = v2.uv[2]
            }

            local screenV3 = {
                x = (p3[1] / p3[4] + 1) * width * 0.5,
                y = (1 - p3[2] / p3[4]) * height * 0.5,
                z = p3[3] / p3[4],
                w = 1 / p3[4],
                u = v3.uv[1],
                v = v3.uv[2]
            }

            -- Backface culling
            local edge1x = screenV2.x - screenV1.x
            local edge1y = screenV2.y - screenV1.y
            local edge2x = screenV3.x - screenV1.x
            local edge2y = screenV3.y - screenV1.y
            local cross = edge1x * edge2y - edge1y * edge2x

            if cross > 0 then
                drawTriangle(screenV1, screenV2, screenV3, texture)
                trianglesDrawn = trianglesDrawn + 1
            end
        end
    end

    -- Debug output (only print occasionally to avoid spam)
    if math.random() < 0.01 then
        print("Triangles drawn: " .. trianglesDrawn)
    end

    -- Update canvas with rendered image
    local image = love.graphics.newImage(imageData)
    image:setFilter("nearest", "nearest")

    love.graphics.setCanvas(canvas)
    love.graphics.clear()
    love.graphics.draw(image, 0, 0)
    love.graphics.setCanvas()

    love.graphics.draw(canvas, 0, 0)
end

return renderer
