module TrainRun

include("./types.jl")
include("./Input.jl")
include("./Preparation.jl")
include("./OperationModes.jl")
include("./Output.jl")


using .types
using .Input
using .Preparation
using .OperationModes
using .Output

export calculateDrivingDynamics

# approximationLevel = 6  # value for approximation to intersections
    # TODO:  define it here and give it to each function? (MovingPhases, EnergySaving)

"""
    calculateDrivingDynamics(trainFilePath::String, pathFilePath::String, settingsFilePath::String)

Calculate the driving dynamics of a train run on a path with special settings with information from the corresponding YAML files with the file paths `trainFilePath`, `pathFilePath`, `settingsFilePath`.

# Examples
```julia-repl
julia> calculateDrivingDynamics(C:\\folder\\train.yaml, C:\\folder\\path.yaml, C:\\folder\\settings.yaml)
todo !!!
```
"""
function calculateDrivingDynamics(trainFilePath::String, pathFilePath::String, settingsFilePath::String)
    print("\n\n\n")

    # input
    (train, path, settings)=readInput(trainFilePath, pathFilePath, settingsFilePath)
    println("The input has been saved.")


    # preparing the input data
    movingSection=preparateSections(path, train, settings)
    println("The moving section has been prepared.")

    if settings.operationModeMinimumRunningTime==true || settings.operationModeMinimumEnergyConsumption==true
        (movingSectionMinimumRunningTime, drivingCourseMinimumRunningTime)=simulateMinimumRunningTime!(movingSection, settings, train)
       # println("t_total=", drivingCourseMinimumRunningTime[end].t)
       # printSectionInformation(movingSectionMinimumRunningTime)
        println("The driving course for the shortest running time has been calculated.")
    end #if


    # oparation mode "minimum energy consumption"
    if settings.operationModeMinimumEnergyConsumption==true
        (movingSectionMinimumEnergyConsumption, drivingCourseMinimumEnergyConsumption)=simulateMinimumEnergyConsumption(movingSectionMinimumRunningTime, drivingCourseMinimumRunningTime, settings, train)
       # printSectionInformation(movingSectionMinimumEnergyConsumption)
        println("The driving course for lowest the energy consumption has been calculated.")
    end #if

    #output
    if settings.operationModeMinimumRunningTime==true && settings.operationModeMinimumEnergyConsumption==true
        plotDrivingCourse(drivingCourseMinimumRunningTime, drivingCourseMinimumEnergyConsumption)
        return createOutput(settings, path.name, train.name, drivingCourseMinimumRunningTime, movingSectionMinimumRunningTime, drivingCourseMinimumEnergyConsumption, movingSectionMinimumEnergyConsumption)
    elseif settings.operationModeMinimumRunningTime==true
        plotDrivingCourse(drivingCourseMinimumRunningTime)
        return createOutput(settings, path.name, train.name, drivingCourseMinimumRunningTime, movingSectionMinimumRunningTime)
    elseif settings.operationModeMinimumEnergyConsumption==true
        plotDrivingCourse(drivingCourseMinimumEnergyConsumption)
        return createOutput(settings, path.name, train.name, drivingCourseMinimumEnergyConsumption, movingSectionMinimumEnergyConsumption)
    else
        println("No Output was demanded. So no output is created.")
        return Dict()
    end
end # function calculateDrivingDynamics

end # module TrainRun
