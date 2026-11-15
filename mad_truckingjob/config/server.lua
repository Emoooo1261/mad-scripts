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
    },
}
