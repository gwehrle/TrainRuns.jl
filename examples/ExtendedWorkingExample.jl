#!/usr/bin/env julia
# -*- coding: UTF-8 -*-
# __julia-version__ = 1.7.0
# __author__        = "Max Kannenberg"
# __copyright__     = "2021"
# __license__       = "ISC"

include("../src/TrainRun.jl")
using .TrainRun

allPaths=[]
push!(allPaths, "data/paths/path_1_10km_nConst_vConst.yaml")
push!(allPaths, "data/paths/path_2_10km_nVar_vConst.yaml")
push!(allPaths, "data/paths/path_3_10km_nConst_vVar.yaml")
push!(allPaths, "data/paths/path_4_real_Germany_EastSaxony_DG-DN.yaml")

allSettings=[]
push!(allSettings, "data/settings.yaml")

allTrains=[]
push!(allTrains, "data/trains/train_freight_V90withOreConsist.yaml")
push!(allTrains, "data/trains/train_passenger_SiemensDesiroClassic.yaml")
push!(allTrains, "data/trains/train_passenger_IC2.yaml")

for pathDirectory in allPaths
    # println(" -    -    -     -     -     -      -     -    -")
    # println("path: ", pathDirectory)
   for trainDirectory in allTrains
       # println("train: ", trainDirectory)
       for settingsDirectory in allSettings
           testDict=calculateDrivingDynamics(trainDirectory, pathDirectory, settingsDirectory)

           sleep(2)

           # println("")
           # println("")
           # println("")
       end
   end
   # println("")
end

# println("")
# println("________________________")
# println("")