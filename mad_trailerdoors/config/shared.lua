return {
    TargetDistance = 3.0,
    InteractionDistance = 10.0,
    TargetLabelOpen = 'Open trailer doors',
    TargetLabelClose = 'Close trailer doors',
--    TrailerModels = {[`trailers2`],
--                      [`trailers3`],
--                      [`trailers5`],
--                      [`tvtrailer`],
--                      [`tvtrailer2`],}
-- IDK this is "Jenkins One At A Time hash function" and reutnrs the model's numeric hash
-- the previous list uses FiveM's backtick hash-literal syntax, which is also intended to produce a hash BUT IT DOESN'T WORK FOR SOME REASON??? MAYBE RESTART FIXES IT? IDC.
    TrailerModels = {joaat('trailers2'),
                    joaat('trailers3'),
                    joaat('trailers5'),
                    joaat('tvtrailer'),
                    joaat('tvtrailer2')},
    ModelDoors = {["trailers2"] = {2, 3},
                    ["trailers3"] = {5},
                    ["trailers5"] = {2, 3},
                    ["tvtrailer"] = {2, 3},
                    ["tvtrailer2"] = {2, 3},},
    StateBag = 'trailerDoorsOpen'
}