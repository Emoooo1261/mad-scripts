return {
    bossPeds = {
        {
            id = 1,  -- City docks boss
            model = 's_m_m_dockwork_01',
            coords = vec4(1240.95, -3322.31, 6.03, 271.43),
            scenario = 'WORLD_HUMAN_CLIPBOARD',
            targetDistance = 15,
            truckSpawnCoords = {vec4(1283.20, -3312.0, 6.0, 359.0),
                                vec4(1268.20, -3312.0, 6.0, 359.0),
                                vec4(1272.52, -3339.15, 6.0, 90.0)},
            trailerSpawnCoords = {vec4(1283.0, -3324.0, 6.0, 359.0), -- Y is offset by 15 for the trailer to be behind the truck. could also just calculate this instead of hardcoding
                                vec4(1268.0, -3324.0, 6.0, 359.0),
                                vec4(1284.52, -3339.16, 6.0, 90.0)},
            contracts = {{
                            title = 'City docks delivery',
                            description = 'Delivery to City Docks #1',
                            deliveries = {vec3(1245.29, -3293.89, 4.71),
                                            vec3(1244.82, -3262.73, 4.67),
                                            vec3(1201.4, -3181.1, 4.69)},
                        },
                    },
        },
        {
            id = 2,  -- Paleto boss
            model = 's_m_m_dockwork_01',
            coords = vec4(122.26, 6405.8, 31.30, 309.76),
            scenario = 'WORLD_HUMAN_CLIPBOARD',
            targetDistance = 15,
            truckSpawnCoords = {vec4(156.18, 6435.58, 30.3, 72.6),
                                vec4(142.8, 6429.29, 30.3, 72.6),
                                vec4(140.42, 6419.63, 30.3, 72.6)},
            trailerSpawnCoords = {vec4(167.64, 6432.0, 30.3, 72.6),
                                    vec4(154.25, 6425.71, 30.3, 72.6),
                                    vec4(151.88, 6416.05, 30.3, 72.6)},
            contracts = {{
                            title = 'Paleto delivery',
                            description = 'Delivery to Paleto',
                            deliveries = {vec3(184.05, 6394.82, 30.38)},
                        },
                    },
        },
        {
            id = 3,  -- Paleto boss 2
            model = 's_m_m_dockwork_01',
            coords = vec4(186.52, 2786.35, 45.9, 273.97),
            scenario = 'WORLD_HUMAN_CLIPBOARD',
            targetDistance = 15,
            truckSpawnCoords = {vec4(198.08, 2787.76, 45.0, 98.5),
                                vec4(196.27, 2800.54, 45.0, 98.5)},
            trailerSpawnCoords = {vec4(210.02, 2789.04, 45.0, 98.5),
                                  vec4(208.11, 2802.5, 45.0, 98.5)},
            contracts = {{
                            title = 'Sandy delivery',
                            description = 'Delivery to Sandy Shores',
                            deliveries = {vec3(186.35, 2796.38, 44.66)},
                        },
                    },
        },
    },
}