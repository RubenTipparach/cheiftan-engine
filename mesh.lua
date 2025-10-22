-- Mesh definitions

local mesh = {}

function mesh.createCube()
    -- Define vertices of a cube
    local vertices = {
        -- Front face
        {pos = {-1, -1, 1}, uv = {0, 1}},
        {pos = {1, -1, 1}, uv = {1, 1}},
        {pos = {1, 1, 1}, uv = {1, 0}},
        {pos = {-1, 1, 1}, uv = {0, 0}},

        -- Back face
        {pos = {1, -1, -1}, uv = {0, 1}},
        {pos = {-1, -1, -1}, uv = {1, 1}},
        {pos = {-1, 1, -1}, uv = {1, 0}},
        {pos = {1, 1, -1}, uv = {0, 0}},

        -- Top face
        {pos = {-1, 1, 1}, uv = {0, 1}},
        {pos = {1, 1, 1}, uv = {1, 1}},
        {pos = {1, 1, -1}, uv = {1, 0}},
        {pos = {-1, 1, -1}, uv = {0, 0}},

        -- Bottom face
        {pos = {-1, -1, -1}, uv = {0, 1}},
        {pos = {1, -1, -1}, uv = {1, 1}},
        {pos = {1, -1, 1}, uv = {1, 0}},
        {pos = {-1, -1, 1}, uv = {0, 0}},

        -- Right face
        {pos = {1, -1, 1}, uv = {0, 1}},
        {pos = {1, -1, -1}, uv = {1, 1}},
        {pos = {1, 1, -1}, uv = {1, 0}},
        {pos = {1, 1, 1}, uv = {0, 0}},

        -- Left face
        {pos = {-1, -1, -1}, uv = {0, 1}},
        {pos = {-1, -1, 1}, uv = {1, 1}},
        {pos = {-1, 1, 1}, uv = {1, 0}},
        {pos = {-1, 1, -1}, uv = {0, 0}}
    }

    -- Define triangles (indices into vertices array)
    local triangles = {
        -- Front face
        {1, 2, 3}, {1, 3, 4},
        -- Back face
        {5, 6, 7}, {5, 7, 8},
        -- Top face
        {9, 10, 11}, {9, 11, 12},
        -- Bottom face
        {13, 14, 15}, {13, 15, 16},
        -- Right face
        {17, 18, 19}, {17, 19, 20},
        -- Left face
        {21, 22, 23}, {21, 23, 24}
    }

    return {
        vertices = vertices,
        triangles = triangles
    }
end

return mesh
