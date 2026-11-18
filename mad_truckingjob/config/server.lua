return {
    vehicles = {
        trucks = {'hauler', 'hauler2'},
        truckType = 'automobile',
        trailers = {'trailers2', 'trailers3'},
        trailerType = 'trailer',
        spawnAreaSize = vec3(8, 30, 12),
        truckSpawnCoords = {vec4(1283.0, -3314.0, 5.14, 359.0),
                            vec4(1268.0, -3314.0, 5.14, 359.0)},
        trailerSpawnCoords = {vec4(1283.0, -3324.0, 5.14, 359.0), -- Y is offset by 15 for the trailer to be behind the truck. could also just calculate this instead of hardcoding
                              vec4(1268.0, -3324.0, 5.14, 359.0)},
        paletoTrailerSpawnCoords = {vec4(167.64, 6432.0, 30.3, 72.6),
                                    vec4(154.25, 6425.71, 30.3, 72.6),
                                    vec4(151.88, 6416.05, 30.3, 72.6)}
    },
}
