--- Coordinates for easy in game debugging
return {
    bossPeds = {
        {
            id = 1,  -- City docks boss
            model = 's_m_m_dockwork_01',
            coords = vec4(1240.95, -3322.31, 6.03, 271.43),
            scenario = 'WORLD_HUMAN_CLIPBOARD',
            targetDistance = 15,
            contracts = {{
                            title = 'Contract #1',
                            description = 'Delivery to City Docks #1',
                            deliveries = {vec3(1278.0, -3277.86, 5.14),
                                            vec3(1278.0, -3277.86, 5.14),},
                            truckSpawnCoords = {vec4(1240.81, -3341.1, 4.8, 269.48)},
                            trailerSpawnCoords = {vec4(1225.81, -3341.1, 4.8, 269.48)},
                        },
                    },
        },
        {
            id = 2,  -- Paleto boss
            model = 's_m_m_dockwork_01',
            coords = vec4(1245.95, -3322.31, 6.03, 271.43),
            scenario = 'WORLD_HUMAN_CLIPBOARD',
            targetDistance = 15,
            contracts = {{
                            title = 'Contract #2',
                            description = 'This is decription for Contract #2',
                            deliveries = {vec3(1278.0, -3277.86, 5.14)},
                            truckSpawnCoords = {vec4(1259.96, -3318.47, 4.8, 358.77)},
                            trailerSpawnCoords = {vec4(1259.96, -3333.47, 4.8, 358.77)}
                        },
                    },
        },
        {
            id = 3,  -- Paleto boss 2
            model = 's_m_m_dockwork_01',
            coords = vec4(1250.95, -3322.31, 6.03, 271.43),
            scenario = 'WORLD_HUMAN_CLIPBOARD',
            targetDistance = 15,
            contracts = {{
                            title = 'Contract #3',
                            description = 'This is decription for Contract #3',
                            deliveries = {vec3(1278.0, -3277.86, 5.14)},
                            truckSpawnCoords = {vec4(1274.93, -3317.42, 4.9, 350.94)},
                            trailerSpawnCoords = {vec4(1274.93, -3332.42, 4.9, 350.94)}
                        },
                    },
        },
    },
}
