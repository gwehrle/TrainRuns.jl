module MovingPhases

using ..types
export addAccelerationPhase!, addAccelerationPhaseUntilBraking!, addCruisingPhase!, addCoastingPhaseUntilBraking!, addBrakingPhase!

v00=100/3.6     # velocity constant (in m/s)
g=9.81          # acceleration due to gravity (in m/s^2)            # TODO: should more digits of g be used?  g=9,80665 m/s^2

approximationLevel = 6  # value for approximation to intersections TODO further explanation (e.g. approximationLevel = 3 -> with stepSize 10 m the approximation will be calculated accurate on 10 mm ; 1s -> 1 ms; 1 km/h -> 3.6 mm/s)
    # TODO: define it in TrainRun and give it to each function?

## functions for calculating tractive effort and resisting forces
"""
calculate the trains tractive effort dependend on the velocity
"""
function calculateTractiveEffort(v::AbstractFloat, tractiveEffortArray)
    for row in 1:length(tractiveEffortArray)
        if  tractiveEffortArray[row][1]<=v && v<=tractiveEffortArray[row][2]
            return tractiveEffortArray[row][3]
        elseif tractiveEffortArray[row][1]>v
            if row>1
                # interpolate for a straight line between the two surrounding points with the formula: F=(v-v_(row-1))*(F_row-_(row-1))/(v_row-v_(row-1))+F_(row-1)
                F_T_interpolation=(v-tractiveEffortArray[row-1][2])*(tractiveEffortArray[row][3]-tractiveEffortArray[row-1][3])/(tractiveEffortArray[row][1]-tractiveEffortArray[row-1][2])+tractiveEffortArray[row-1][3]
                return F_T_interpolation
            else
                return tractiveEffortArray[1][3]
            end #if
        end #if
    end #for
end #function calculateTractiveEffort

"""
calculate and return the traction units vehicle resistance dependend on the velocity
"""
function calculateTractionUnitResistance(v::AbstractFloat, train::Train)
    return train.f_Rtd0/1000*train.m_td*g+train.f_Rtc0/1000*train.m_tc*g+train.F_Rt2*((v+train.Δv_t)/v00)^2    # /1000 because of the unit ‰
end #function calculateTractionUnitResistance

"""
calculate and return the wagons vehicle resistance dependend on the velocity
"""
function calculateWagonsResistance(v::AbstractFloat, train::Train)
    return train.m_w*g*(train.f_Rw0/1000+train.f_Rw1/1000*v/v00+train.f_Rw2/1000*((v+train.Δv_w)/v00)^2)          # /1000 because of the unit ‰
end #function calculateWagonsResistance

"""
calculate and return the path resistance dependend on the trains position and mass model
"""
function calculatePathResistance(s::AbstractFloat, massModel::String, train::Train, allCs::Vector{CharacteristicSection})
    # looking for the characteristic section with the trains head position
    id=length(allCs)
    while s<allCs[id].s_start
        id=id-1
        if id==0
            println("s=",s,"   MS.s_start=",allCs[1].s_start)
        end
    end #while

    if massModel=="mass point"
        pathResistance=allCs[id].f_Rp/1000*train.m_union*g        # /1000 because of the unit ‰
    elseif massModel=="homogeneous strip"
        pathResistance=0.0
        while id>0 && s-train.l_union<allCs[id].s_end
            pathResistance=pathResistance+(min(s, allCs[id].s_end)-max(s-train.l_union, allCs[id].s_start))/train.l_union*(allCs[id].f_Rp/1000*train.m_union*g)      # /1000 because of the unit ‰
            id=id-1
            if id==0
                # TODO: currently for values  < movingSection.s_start the values of movingSection.s_start  will be used
                return pathResistance+(allCs[1].s_start-(s-train.l_union))/train.l_union*(allCs[1].f_Rp/1000*train.m_union*g)        # /1000 because of the unit ‰
            end #if
        end #while
    else
        error("ERROR at the calculation of path resistance: settings.massModel!=mass point && settings.massModel!=homogeneous strip")
    end #if

    return pathResistance
end #function pathResistance

"""
calculate and return tractive and resisting forces for a waypoint
"""
function calculateForces!(waypoint::Waypoint, train::Train, massModel::String,  allCs::Vector{CharacteristicSection}, bsType::String)
    # calculate resisting forces
    waypoint.F_Rt=calculateTractionUnitResistance(waypoint.v, train)
    waypoint.F_Rw=calculateWagonsResistance(waypoint.v, train)
    waypoint.F_Runion=waypoint.F_Rt+waypoint.F_Rw
    waypoint.F_Rp=calculatePathResistance(waypoint.s, massModel, train, allCs)
    waypoint.F_R=waypoint.F_Runion+waypoint.F_Rp

    #calculate tractive effort
    if bsType == "acceleration"
        waypoint.F_T = calculateTractiveEffort(waypoint.v, train.tractiveEffortArray)
    elseif bsType == "cruising"
        waypoint.F_T = min(max(0.0, waypoint.F_R), calculateTractiveEffort(waypoint.v, train.tractiveEffortArray))
    else
        waypoint.F_T = 0.0
    end
return waypoint
end #function calculateForces


"""
TODO
"""
function moveAStep(previousPoint::Waypoint, stepVariable::String, stepSize::AbstractFloat, csId::Integer)
    # stepSize is the currentStepSize depending on the accessing function
    # TODO: csId is only for error messages. Should it be removed?

    # creating the next waypoint
    newPoint=Waypoint()
    newPoint.i=previousPoint.i+1         # identifier

    # calculate s, t, v, E
    if stepVariable=="s in m"                                                           # distance step method
        newPoint.Δs=stepSize                                                                # step size (in m)
        # TODO: is this if correct and necessary?
            #if ((previousPoint.v/previousPoint.a)^2+2*newPoint.Δs/previousPoint.a)<0.0 || (previousPoint.v^2+2*newPoint.Δs*previousPoint.a)<0.0  # checking if the parts of the following square roots will be <0.0
            #    error("ERROR: The train stops during the acceleration phase in CS",csId," because the tractive effort is lower than the resistant forces.",
            #    "       Before the stop the last point has the values s=",previousPoint.s," m,  v=",previousPoint.v," m/s,  a=",previousPoint.a," m/s^2,",
            #    "       F_T=",previousPoint.F_T," N,  F_Rt=",previousPoint.F_Rt," N,  F_Rw=",previousPoint.F_Rw," N,  F_Rp=",previousPoint.F_Rp," N.")
            #end
            #= 08/31 TODO: How to check if the train stopps during this step? I should throw an error myself that I catch in higher hierarchies.
            =#
        newPoint.Δt=sign(previousPoint.a)*sqrt((previousPoint.v/previousPoint.a)^2+2*newPoint.Δs/previousPoint.a)-previousPoint.v/previousPoint.a                          # step size (in s)
        newPoint.Δv=sqrt(previousPoint.v^2+2*newPoint.Δs*previousPoint.a)-previousPoint.v   # step size (in m/s)
    elseif stepVariable=="t in s"                                                       # time step method
        newPoint.Δt=stepSize                                                                # step size (in s)
        newPoint.Δs=newPoint.Δt*(2*previousPoint.v+newPoint.Δt*previousPoint.a)/2           # step size (in m)
        newPoint.Δv=newPoint.Δt*previousPoint.a                                             # step size (in m/s)
    elseif stepVariable=="v in m/s"                                                     # velocity step method
        newPoint.Δv=stepSize*sign(previousPoint.a)                                          # step size (in m/s)
        newPoint.Δs=((previousPoint.v+newPoint.Δv)^2-previousPoint.v^2)/2/previousPoint.a   # step size (in m)
        newPoint.Δt=newPoint.Δv/previousPoint.a                                             # step size (in s)
    end #if

    newPoint.s=previousPoint.s+newPoint.Δs                            # position (in m)
    newPoint.t=previousPoint.t+newPoint.Δt                            # point in time (in s)
    newPoint.v=previousPoint.v+newPoint.Δv                            # velocity (in m/s)
    # 08/23 the following will be checked later
    #if newPoint.v<=0.0
    #    error("ERROR: The train stops during the acceleration phase in CS",csId," m because the tractive effort is lower than the resistant forces.",
    #    "       Before the stop the last point has the values s=",previousPoint.s,"  v=",previousPoint.v," m/s  a=",previousPoint.a," m/s^2",
    #    "       F_T=",previousPoint.F_T," N  F_Rt=",previousPoint.F_Rt," N  F_Rw=",previousPoint.F_Rw," N  F_Rp=",previousPoint.F_Rp," N.")
    #end
    newPoint.ΔW_T=previousPoint.F_T*newPoint.Δs                       # mechanical work in this step (in Ws)
    newPoint.W_T=previousPoint.W_T+newPoint.ΔW_T                      # mechanical work (in Ws)
    newPoint.ΔE=newPoint.ΔW_T                                         # energy consumption in this step (in Ws)
    newPoint.E=previousPoint.E+newPoint.ΔE                            # energy consumption (in Ws)

    return newPoint
end #function moveAStep


"""
# if the tail of the train is still located in a former characteristic section it has to be checked if its speed limit can be kept
"""
function detectFormerSpeedLimits(allCs::Vector{CharacteristicSection}, csWithTrainHeadId::Integer, currentPoint::Waypoint, l_union::AbstractFloat)
    formerSpeedLimits=[]
    if csWithTrainHeadId > 1 && currentPoint.s - l_union < allCs[csWithTrainHeadId].s_start
    #    if abs(allCs[csWithTrainHeadId-1].v_limit-currentPoint.v)<0.000001 # if the train runs already at the previous sections limit
        #    s_braking=max(0.0, ceil((allCs[csWithTrainHeadId].v_exit^2-currentPoint.v^2)/2/train.a_braking, digits=approximationLevel))
        #    s_cruisingBeforeAcceleration=min(l_union, allCs[csWithTrainHeadId].s_end-currentPoint.s-s_braking)

        #    return [], s_cruisingBeforeAcceleration
    #    else # if the train runs slower than allowed in the previous section the lower speed limits of the other sections will be detected
        #    formerSpeedLimits=[]
            formerCsId=csWithTrainHeadId-1
            while formerCsId > 0 && currentPoint.s - l_union < allCs[formerCsId].s_end
                if allCs[formerCsId].v_limit < allCs[csWithTrainHeadId].v_limit    # TODO: is the position of trains tail < movingSection.s_start, v_limit of the first CS is used
                    push!(formerSpeedLimits, [allCs[formerCsId].s_end, allCs[formerCsId].v_limit])
                    for i in 1:length(formerSpeedLimits)-1
                        if formerSpeedLimits[i][2]<=formerSpeedLimits[end][2]
                            pop!(formerSpeedLimits)
                            break
                        end
                    end
                end
                formerCsId=formerCsId-1
            end
        #    return (formerSpeedLimits, 0.0)

    #    end
    end
    #return ([], 0.0)
    return formerSpeedLimits
end # function detectFormerSpeedLimits

function considerFormerSpeedLimits!(characteristicSection::CharacteristicSection, drivingCourse::Vector{Waypoint}, settings::Settings, train::Train, allCs::Vector{CharacteristicSection}, formerSpeedLimits, accelerationSection::BehaviorSection)
 #  TODO: What is the type of formerSpeedLimits?   function considerFormerSpeedLimits!(characteristicSection::CharacteristicSection, drivingCourse::Vector{Waypoint}, settings::Settings, train::Train, allCs::Vector{CharacteristicSection}, formerSpeedLimits::Array{Array{AbstractFloat,1},1}, accelerationSection::BehaviorSection)
 #        would work: function considerFormerSpeedLimits!(characteristicSection::CharacteristicSection, drivingCourse::Vector{Waypoint}, settings::Settings, train::Train, allCs::Vector{CharacteristicSection}, formerSpeedLimits::Array{Any,1}, accelerationSection::BehaviorSection)
    if length(formerSpeedLimits) > 0
        # if a former speed limit has been exceeded the acceleration steps of this CS will be removed and a cruising phase will be inserted before acceleration
        if drivingCourse[end].v > formerSpeedLimits[end][2]

            while drivingCourse[end].s > get(characteristicSection.behaviorSections, "cruisingBeforeAcceleration", accelerationSection).s_start
                pop!(drivingCourse)
            end

            if haskey(characteristicSection.behaviorSections, "cruisingBeforeAcceleration")
                characteristicSection.t_total=characteristicSection.t_total-get(characteristicSection.behaviorSections, "cruisingBeforeAcceleration", BehaviorSection()).t_total       # reducing the total running time (in s)
                characteristicSection.E_total=characteristicSection.E_total-get(characteristicSection.behaviorSections, "cruisingBeforeAcceleration", BehaviorSection()).E_total       # reducing the total energy consumption (in Ws)
                delete!(characteristicSection.behaviorSections, "cruisingBeforeAcceleration")
            end

            # create a (new and longer) cruisingBeforeAcceleration section
            s_braking=max(0.0, ceil((characteristicSection.v_exit^2-drivingCourse[end].v^2)/2/train.a_braking, digits=approximationLevel))
            s_cruisingBeforeAcceleration=min(characteristicSection.s_end-drivingCourse[end].s-s_braking, formerSpeedLimits[end][1]-(drivingCourse[end].s-train.l_union))

            if s_cruisingBeforeAcceleration>0.0
                (characteristicSection, drivingCourse)=addCruisingPhase!(characteristicSection, drivingCourse, s_cruisingBeforeAcceleration, settings, train, allCs, "cruisingBeforeAcceleration")
            else
                error("ERROR: cruisingBeforeAcceleration <=0.0 although it has to be >0.0 in CS ",characteristicSection.id)
            end

            if  drivingCourse[end].s < characteristicSection.s_end
                # reset the accelerationSection
                accelerationSection=BehaviorSection()
                accelerationSection.type="acceleration"             # type of behavior section
                accelerationSection.s_start=drivingCourse[end].s      # first position (in m)
                accelerationSection.v_entry=drivingCourse[end].v      # entry speed (in m/s)

                currentStepSize=settings.stepSize  # initializing the step size that can be reduced near intersections
            else
                return (characteristicSection, drivingCourse, formerSpeedLimits, accelerationSection, true)
            end
        end

        # remove former speed limits of characteristic sections the train has left during the last step from the list
        while length(formerSpeedLimits) > 0 && drivingCourse[end].s - train.l_union >= formerSpeedLimits[end][1]
            pop!(formerSpeedLimits)
        end
    end
    return (characteristicSection, drivingCourse, formerSpeedLimits, accelerationSection, false)
end # function considerFormerSpeedLimits!

## This function calculates the waypoints of the starting phase.
# Therefore it gets its first waypoint and the characteristic section and returns the characteristic section including the behavior section for starting if needed.
# Info: currently the values of the starting phase will be calculated like in the acceleration phase
function addStartingPhase!(characteristicSection::CharacteristicSection, drivingCourse::Vector{Waypoint}, settings::Settings, train::Train, allCs::Vector{CharacteristicSection})
    if drivingCourse[end].v==0.0 && drivingCourse[end].s<characteristicSection.s_end
        startingSection=BehaviorSection()
        startingSection.type="starting"                         # type of behavior section
        startingSection.s_start=drivingCourse[end].s            # first position (in m)
        startingSection.v_entry=drivingCourse[end].v            # entry speed (in m/s)
        push!(startingSection.waypoints, drivingCourse[end].i)  # list of containing waypoints

        # traction effort and resisting forces (in N):
        drivingCourse[end]=Waypoint(calculateForces!(drivingCourse[end], train, settings.massModel,  allCs, "acceleration"))    # currently the tractive effort is calculated like in the acceleration phase

        # acceleration (in m/s^2):
        drivingCourse[end].a=(drivingCourse[end].F_T-drivingCourse[end].F_R)/train.m_union/train.ξ_union
        if drivingCourse[end].a<0.0
            error("ERROR: a<0 m/s^2 in the starting phase !")
        elseif drivingCourse[end].a==0.0
            error("ERROR: a=0 m/s^2 in the starting phase !")
        end

        # creating the next waypoint
        push!(drivingCourse, moveAStep(drivingCourse[end], settings.stepVariable, settings.stepSize, characteristicSection.id))
           #= 07/30 TODO: the calculation is easier with these lines because the values that are 0 in the first step are not used in calculation but all in all the code gets easier without these lines:
            push!(drivingCourse, Waypoint())
            drivingCourse[end].i=drivingCourse[end-1].i+1     # incrementing the number of the waypoint

            # calculate s, t, v, E
            if settings.stepVariable=="s in m"                                                           # distance step method
                drivingCourse[end].Δs=settings.stepSize                                                     # step size (in m)
                drivingCourse[end].Δt=sqrt(2*drivingCourse[end].Δs/drivingCourse[end-1].a)                  # step size (in s)    (in this formula drivingCourse[end-1].v is missing because it is 0.0)
                drivingCourse[end].Δv=sqrt(2*drivingCourse[end].Δs*drivingCourse[end-1].a)                  # step size (in m/s)  (in this formula drivingCourse[end-1].v is missing because it is 0.0)
            elseif settings.stepVariable=="t in s"                                                       # time step method
                drivingCourse[end].Δt=settings.stepSize                                                     # step size (in s)
                drivingCourse[end].Δs=drivingCourse[end].Δt*(drivingCourse[end].Δt*drivingCourse[end-1].a)/2  # step size (in m)
                drivingCourse[end].Δv=drivingCourse[end].Δt*drivingCourse[end-1].a                          # step size (in m/s)
            elseif settings.stepVariable=="v in m/s"                                                     # velocity step method
                drivingCourse[end].Δv=settings.stepSize*sign(drivingCourse[end-1].a)                        # step size (in m/s)
                drivingCourse[end].Δs=drivingCourse[end].Δv^2/2/drivingCourse[end-1].a                      # step size (in m)
                drivingCourse[end].Δt=drivingCourse[end].Δv/drivingCourse[end-1].a                          # step size (in s)
            end #if

            #drivingCourse[end].s=ceil(drivingCourse[end-1].s+drivingCourse[end].Δs, digits=approximationLevel)          # position (in m)  # rounded -> exact to 1 nm
            drivingCourse[end].s=drivingCourse[end-1].s+drivingCourse[end].Δs                            # position (in m)
            drivingCourse[end].t=drivingCourse[end-1].t+drivingCourse[end].Δt                            # point in time (in s)
            drivingCourse[end].v=drivingCourse[end-1].v+drivingCourse[end].Δv                            # velocity (in m/s)
            drivingCourse[end].ΔW_T=drivingCourse[end-1].F_T*drivingCourse[end].Δs                       # mechanical work in this step (in Ws)
            drivingCourse[end].W_T=drivingCourse[end-1].W_T+drivingCourse[end].ΔW_T                      # mechanical work (in Ws)
            drivingCourse[end].ΔE=drivingCourse[end].ΔW_T                                                # energy consumption in this step (in Ws)
            drivingCourse[end].E=drivingCourse[end-1].E+drivingCourse[end].ΔE                            # energy consumption (in Ws)
            =#
        push!(startingSection.waypoints, drivingCourse[end].i)

        # calculate the accumulated starting section information
        startingSection.s_end=drivingCourse[end].s                                                  # last position (in m)
        startingSection.s_total=startingSection.s_end-startingSection.s_start                       # total length  (in m)
        startingSection.v_exit=drivingCourse[end].v                                                 # exit speed (in m/s)
        startingSection.t_total=drivingCourse[end].t-drivingCourse[startingSection.waypoints[1]].t  # total running time (in s)
        startingSection.E_total=drivingCourse[end].E-drivingCourse[startingSection.waypoints[1]].E  # total energy consumption (in Ws)

        characteristicSection.t_total=characteristicSection.t_total+startingSection.t_total         # total running time (in s)
        characteristicSection.E_total=characteristicSection.E_total+startingSection.E_total         # total energy consumption (in Ws)

        merge!(characteristicSection.behaviorSections, Dict("starting"=>startingSection))
    end # else: return the characteristic section without a starting section
    return (characteristicSection, drivingCourse)
end #function addStartingPhase!


## This function calculates the waypoints of the acceleration phase.
 #  Therefore it gets its previous driving course and the characteristic section and returns the characteristic section and driving course including the acceleration section
function addAccelerationPhase!(characteristicSection::CharacteristicSection, drivingCourse::Vector{Waypoint}, settings::Settings, train::Train, allCs::Vector{CharacteristicSection})
    if drivingCourse[end].v==0.0
        (characteristicSection, drivingCourse)=addStartingPhase!(characteristicSection, drivingCourse, settings, train, allCs)
    end #if

    # if the tail of the train is still located in a former characteristic section it has to be checked if its speed limit can be kept
 #    (formerSpeedLimits, s_cruisingBeforeAcceleration) = detectFormerSpeedLimits(allCs, characteristicSection.id, drivingCourse[end], train.l_union)
    formerSpeedLimits = detectFormerSpeedLimits(allCs, characteristicSection.id, drivingCourse[end], train.l_union)
 #    if s_cruisingBeforeAcceleration > 0.0
 #        (characteristicSection, drivingCourse)=addCruisingPhase!(characteristicSection, drivingCourse, s_cruisingBeforeAcceleration, settings, train, allCs, "cruisingBeforeAcceleration")
    #else
    #    error("ERROR: cruisingBeforeAcceleration <=0.0 although it has to be >0.0 in CS ",csWithTrainHeadId)
 #    end

    if drivingCourse[end].v < characteristicSection.v_reach && drivingCourse[end].s <characteristicSection.s_end
        accelerationSection=BehaviorSection()
        accelerationSection.type="acceleration"               # type of behavior section
        accelerationSection.s_start=drivingCourse[end].s      # first position (in m)
        accelerationSection.v_entry=drivingCourse[end].v      # entry speed (in m/s)
        push!(accelerationSection.waypoints, drivingCourse[end].i)

        currentStepSize=settings.stepSize  # initializing the step size that can be reduced near intersections
        #= 08/23 old version for intersection approximation
        for cycle in 1:5                    # first cycle with normal step size, second cycle with reduced step size, third cycle with more reduced step size and fourth cycle with the last step size calculated till the intersection
                                            # in the fifth cycle the interpolated values are corrected in case v_reach is still to high although s==s_end
                                            =#
        for cycle in 1:approximationLevel+1   # first cycle with normal step size followed by cycles with reduced step size depending on the level of approximation
        #    while characteristicSection.v_reach - drivingCourse[end].v > 0.000001 && drivingCourse[end].s<characteristicSection.s_end && drivingCourse[end].v>0.0
            while drivingCourse[end].v<characteristicSection.v_reach && drivingCourse[end].s<characteristicSection.s_end && drivingCourse[end].v>0.0

                # traction effort and resisting forces (in N)
                drivingCourse[end]=Waypoint(calculateForces!(drivingCourse[end], train, settings.massModel,  allCs, accelerationSection.type))

                # acceleration (in m/s^2):
                drivingCourse[end].a=(drivingCourse[end].F_T-drivingCourse[end].F_R)/train.m_union/train.ξ_union
                if drivingCourse[end].a==0.0
                    error("ERROR: a=0 m/s^2 in the acceleration phase !   with  F_T=",drivingCourse[end].F_T,"  F_Rt=",drivingCourse[end].F_Rt,"  F_Rw=",drivingCourse[end].F_Rw,"  F_Rp=",drivingCourse[end].F_Rp)
                end

                # create the next waypoint
                push!(drivingCourse, moveAStep(drivingCourse[end], settings.stepVariable, currentStepSize, characteristicSection.id))
                push!(accelerationSection.waypoints, drivingCourse[end].i)

                if length(formerSpeedLimits) > 0 # If the tail of the train is located in a former characteristic section with lower speed limit check if is is possible to accelerate as normal
                    (characteristicSection, drivingCourse, formerSpeedLimits, accelerationSection, endOfCsReached) = considerFormerSpeedLimits!(characteristicSection, drivingCourse, settings, train, allCs, formerSpeedLimits, accelerationSection)

                    if  endOfCsReached
                        return (characteristicSection, drivingCourse)
                    end #if
                end #if
            end #while

            # check which limit was reached and adjust the currentStepSize for the next cycle
            if cycle < approximationLevel+1
                if drivingCourse[end].v<=0.0
                    currentStepSize = settings.stepSize / 10.0^cycle

                elseif drivingCourse[end].s>characteristicSection.s_end
                    if settings.stepVariable == "s in m"
                        currentStepSize=characteristicSection.s_end-drivingCourse[end-1].s
                    else
                        currentStepSize = settings.stepSize / 10.0^cycle
                    end

                elseif drivingCourse[end].v>characteristicSection.v_reach
                    if settings.stepVariable=="v in m/s"
                        currentStepSize=characteristicSection.v_reach-drivingCourse[end-1].v
                    else
                        currentStepSize = settings.stepSize / 10.0^cycle
                    end

                elseif drivingCourse[end].s==characteristicSection.s_end
                    break

                elseif drivingCourse[end].v==characteristicSection.v_reach
                    break

                else
                    error("ERROR at acceleration phase: With the step variable ",settings.stepVariable," the while loop will be left although v<v_reach and s<s_end in CS",characteristicSection.id,"  with s=" ,drivingCourse[end].s," m and v=",drivingCourse[end].v," m/s")
                end
                # delete last waypoint for recalculating the last step with reduced step size
                pop!(drivingCourse)
                pop!(accelerationSection.waypoints)

            else # if the level of approximation is reached
                if drivingCourse[end].v<=0.0
                    # push!(accelerationSection.waypoints, drivingCourse[end].i)
                    error("ERROR: The train stops during the acceleration phase in CS",characteristicSection.id," because the tractive effort is lower than the resistant forces.",
                    "       Before the stop the last point has the values s=",drivingCourse[end-1].s," m  v=",drivingCourse[end-1].v," m/s  a=",drivingCourse[end-1].a," m/s^2",
                    "       F_T=",drivingCourse[end-1].F_T," N  F_Rt=",drivingCourse[end-1].F_Rt," N  F_Rw=",drivingCourse[end-1].F_Rw," N  F_Rp=",drivingCourse[end-1].F_Rp," N.")

                elseif drivingCourse[end].v>characteristicSection.v_reach
                    pop!(drivingCourse)
                    pop!(accelerationSection.waypoints)
                elseif drivingCourse[end].s>characteristicSection.s_end
                    drivingCourse[end].s=characteristicSection.s_end # rounding s down to s_end

                else

                end
            end

            #= 08/23 new, sorted by step variable:
            if drivingCourse[end].v<=0.0
                    currentStepSize=currentStepSize/10.0
                pop!(drivingCourse)
                pop!(accelerationSection.waypoints)

            elseif settings.stepVariable == "s in m"
                if drivingCourse[end].s > characteristicSection.s_end
                    currentStepSize=characteristicSection.s_end-drivingCourse[end-1].s
                    pop!(drivingCourse)
                    pop!(accelerationSection.waypoints)
                elseif drivingCourse[end].v > characteristicSection.v_reach
                        currentStepSize = settings.stepSize / 10.0^cycle
                    pop!(drivingCourse)
                    pop!(accelerationSection.waypoints)
                elseif drivingCourse[end].s==characteristicSection.s_end
                    break
                elseif drivingCourse[end].v==characteristicSection.v_reach
                    break
                else
                    error("ERROR at acceleration phase: With the distance step method the while loop will be left although v<v_reach and s<s_end in CS",characteristicSection.id,"  with s=" ,drivingCourse[end].s," m and v=",drivingCourse[end].v," m/s")
                end #if

            elseif settings.stepVariable=="t in s"
                if drivingCourse[end].s>characteristicSection.s_end
                        currentStepSize=currentStepSize/10.0
                    pop!(drivingCourse)
                    pop!(accelerationSection.waypoints)
                elseif drivingCourse[end].v>characteristicSection.v_reach
                        currentStepSize=currentStepSize/10.0
                    pop!(drivingCourse)
                    pop!(accelerationSection.waypoints)
                elseif drivingCourse[end].s==characteristicSection.s_end
                    break
                elseif drivingCourse[end].v==characteristicSection.v_reach
                    break
                else
                    error("ERROR at acceleration phase: With the time step method the while loop will be left although v<v_reach and s<s_end in CS",characteristicSection.id,"  with s=" ,drivingCourse[end].s," m and v=",drivingCourse[end].v," m/s")
                end

            elseif settings.stepVariable=="v in m/s"
                if drivingCourse[end].v > characteristicSection.v_reach
                    currentStepSize=characteristicSection.v_reach-drivingCourse[end-1].v
                    pop!(drivingCourse)
                    pop!(accelerationSection.waypoints)
                elseif drivingCourse[end].s>characteristicSection.s_end
                        currentStepSize = settings.stepSize / 10.0^cycle
                    pop!(drivingCourse)
                    pop!(accelerationSection.waypoints)
                elseif drivingCourse[end].v==characteristicSection.v_reach
                    break
                elseif drivingCourse[end].s==characteristicSection.s_end
                    break
                else
                    error("ERROR at acceleration phase: With the velocity step method the while loop will be left although v<v_reach and s<s_end in CS",characteristicSection.id,"  with s=" ,drivingCourse[end].s," m and v=",drivingCourse[end].v," m/s")
                end #if
            end #if
            =#

            #= 08/23 old version for intersection approximation
            # check which limit was reached and adjust the currentStepSize for the next cycle
            if drivingCourse[end].v<=0.0
                if cycle<3
                    currentStepSize=currentStepSize/10.0
                elseif cycle==3 || cycle==4  # new step size is calculated with interpolation
                    currentStepSize=abs((characteristicSection.v_reach-drivingCourse[end-1].v)*(drivingCourse[end].s-drivingCourse[end-1].s)/(drivingCourse[end].v-drivingCourse[end-1].v))   # step size (in m/s)
                elseif cycle==5
                    error("ERROR: The train stops during the acceleration phase in CS",characteristicSection.id," m because the tractive effort is lower than the resistant forces.",
                    "       Before the stop the last point has the values s=",drivingCourse[end-1].s,"  v=",drivingCourse[end-1].v," m/s  a=",drivingCourse[end-1].a," m/s^2",
                    "       F_T=",drivingCourse[end-1].F_T," N  F_Rt=",drivingCourse[end-1].F_Rt," N  F_Rw=",drivingCourse[end-1].F_Rw," N  F_Rp=",drivingCourse[end-1].F_Rp," N.")
                end
                pop!(drivingCourse)
                pop!(accelerationSection.waypoints)

            elseif settings.stepVariable=="s in m"
                if drivingCourse[end].s>characteristicSection.s_end
                    currentStepSize=characteristicSection.s_end-drivingCourse[end-1].s
                    pop!(drivingCourse)
                    pop!(accelerationSection.waypoints)
                elseif drivingCourse[end].v>characteristicSection.v_reach
                    if cycle<3
                        currentStepSize=currentStepSize/10.0
                    elseif cycle==3 || cycle==4  # new step size is calculated with interpolation
                        currentStepSize=abs((characteristicSection.v_reach-drivingCourse[end-1].v)*(drivingCourse[end].s-drivingCourse[end-1].s)/(drivingCourse[end].v-drivingCourse[end-1].v))   # step size (in m/s)
                    elseif cycle==5
                    end
                    pop!(drivingCourse)
                    pop!(accelerationSection.waypoints)
                elseif drivingCourse[end].s==characteristicSection.s_end
                    break
                elseif drivingCourse[end].v==characteristicSection.v_reach
                    break
                else
                    error("ERROR at acceleration phase: With the distance step method the while loop will be left although v<v_reach and s<s_end in CS",characteristicSection.id,"  with s=" ,drivingCourse[end].s," m and v=",drivingCourse[end].v," m/s")
                end #if

            elseif settings.stepVariable=="t in s"
                if drivingCourse[end].s>characteristicSection.s_end
                    if cycle<=3
                        currentStepSize=currentStepSize/10.0
                    elseif cycle==4                       # new step size is calculated with interpolation
                        currentStepSize=currentStepSize/10.0

                    elseif cycle==5
                        if (drivingCourse[end].s-characteristicSection.s_end)>0.001
                            println("In cycle 5 of the acceleration phase s will be set from ", drivingCourse[end].s, "  to   ",characteristicSection.s_end," because the difference is just ",drivingCourse[end].s-characteristicSection.s_end)
                        end
                        drivingCourse[end].s=characteristicSection.s_end  # rounding s down to s_end
                        break
                    end
                    pop!(drivingCourse)
                    pop!(accelerationSection.waypoints)
                elseif drivingCourse[end].v>characteristicSection.v_reach
                    if cycle<=3
                        currentStepSize=currentStepSize/10.0
                    elseif cycle==4  # new step size is calculated with interpolation
                        currentStepSize=abs((characteristicSection.v_reach-drivingCourse[end-1].v)*(drivingCourse[end].t-drivingCourse[end-1].t)/(drivingCourse[end].v-drivingCourse[end-1].v))    # step size (in s)
                    elseif cycle==5
                    end
                    pop!(drivingCourse)
                    pop!(accelerationSection.waypoints)
                elseif drivingCourse[end].s==characteristicSection.s_end
                    break
                elseif drivingCourse[end].v==characteristicSection.v_reach
                    break
                else
                    error("ERROR at acceleration phase: With the time step method the while loop will be left although v<v_reach and s<s_end in CS",characteristicSection.id,"  with s=" ,drivingCourse[end].s," m and v=",drivingCourse[end].v," m/s")
                end

            elseif settings.stepVariable=="v in m/s"
                if drivingCourse[end].v>characteristicSection.v_reach
                    currentStepSize=characteristicSection.v_reach-drivingCourse[end-1].v
                    pop!(drivingCourse)
                    pop!(accelerationSection.waypoints)
                elseif drivingCourse[end].s>characteristicSection.s_end
                    if cycle<=3
                    #if cycle<3
                        currentStepSize=currentStepSize/10.0
                    elseif cycle==4
                        currentStepSize=currentStepSize/10.0
                    elseif cycle==5
                        drivingCourse[end].s=characteristicSection.s_end # rounding s down to s_end
                        break
                    end
                    pop!(drivingCourse)
                    pop!(accelerationSection.waypoints)
                elseif drivingCourse[end].v==characteristicSection.v_reach
                    break
                elseif drivingCourse[end].s==characteristicSection.s_end
                    break
                else
                    error("ERROR at acceleration phase: With the velocity step method the while loop will be left although v<v_reach and s<s_end in CS",characteristicSection.id,"  with s=" ,drivingCourse[end].s," m and v=",drivingCourse[end].v," m/s")
                end #if
            end #if
            =#
        end #for


        # calculation the accumulated acceleration section information
        accelerationSection.v_exit=drivingCourse[end].v                                                     # exit speed (in m/s)
        accelerationSection.s_end=drivingCourse[end].s                                                      # last position (in m)
        accelerationSection.s_total=accelerationSection.s_end-accelerationSection.s_start                   # total length  (in m)
        accelerationSection.t_total=drivingCourse[end].t-drivingCourse[accelerationSection.waypoints[1]].t  # total running time (in s)
        accelerationSection.E_total=drivingCourse[end].E-drivingCourse[accelerationSection.waypoints[1]].E  # total energy consumption (in Ws)
        characteristicSection.t_total=characteristicSection.t_total+accelerationSection.t_total             # total running time (in s)
        characteristicSection.E_total=characteristicSection.E_total+accelerationSection.E_total             # total energy consumption (in Ws)

        # TODO: this warning schould not be needed. just for testing
        if characteristicSection.v_reach<drivingCourse[end].v
            println("WARNING, v is getting to high at the end of the acceleration phase.   v=",drivingCourse[end].v ,"  > v_reach=",characteristicSection.v_reach)
        end

        merge!(characteristicSection.behaviorSections, Dict("acceleration"=>accelerationSection))
    end # else: just return the given waypoint number without changes due to the acceleration phase

    return (characteristicSection, drivingCourse)
end #function addAccelerationPhase!


## This function calculates the waypoints of the acceleration phase.
function addAccelerationPhaseUntilBraking!(characteristicSection::CharacteristicSection, drivingCourse::Vector{Waypoint}, settings::Settings, train::Train, allCs::Vector{CharacteristicSection})
    if drivingCourse[end].v==0.0
        (characteristicSection, drivingCourse)=addStartingPhase!(characteristicSection, drivingCourse, settings, train, allCs)
    end #if

    # if the tail of the train is still located in a former characteristic section it has to be checked if its speed limit can be kept
    formerSpeedLimits = detectFormerSpeedLimits(allCs, characteristicSection.id, drivingCourse[end], train.l_union)
    #(formerSpeedLimits, s_cruisingBeforeAcceleration) = detectFormerSpeedLimits(allCs, characteristicSection.id, drivingCourse[end], train.l_union)
    #if s_cruisingBeforeAcceleration > 0.0
    #    (characteristicSection, drivingCourse)=addCruisingPhase!(characteristicSection, drivingCourse, s_cruisingBeforeAcceleration, settings, train, allCs, "cruisingBeforeAcceleration")
    #else
    #    error("ERROR: cruisingBeforeAcceleration <=0.0 although it has to be >0.0 in CS ",csWithTrainHeadId)
    #end

    #= 07/30 *** TODO
    # if the tail of the train is still in a former characteristic section it has to be checked if its speed limit can be kept
    formerSpeedLimits=[]
    if characteristicSection.id>1 && drivingCourse[end].s-train.l_union<characteristicSection.s_start
        if abs(allCs[characteristicSection.id-1].v_limit-drivingCourse[end].v)<0.000001
            s_braking=max(0.0, ceil((characteristicSection.v_exit^2-drivingCourse[end].v^2)/2/train.a_braking, digits=approximationLevel))
            s_cruisingBeforeAcceleration=min(characteristicSection.s_end-drivingCourse[end].s-s_braking, train.l_union)

            if s_cruisingBeforeAcceleration>0.0
                (characteristicSection, drivingCourse)=addCruisingPhase!(characteristicSection, drivingCourse, s_cruisingBeforeAcceleration, settings, train, allCs, "cruisingBeforeAcceleration")
            else
                error("ERROR: cruisingBeforeAcceleration <=0.0 although it has to be >0.0 in CS ",characteristicSection.id)
            end
        else # detecting the lower speed limits of former sections
            csId=characteristicSection.id-1
            while csId>0 && drivingCourse[end].s-train.l_union<allCs[csId].s_end
                if allCs[csId].v_limit<characteristicSection.v_limit    # TODO: is the position of trains end < movingSection.s_start, v_limit of the first CS is used
                    push!(formerSpeedLimits, [allCs[csId].s_end, allCs[csId].v_limit])
                    for i in 1:length(formerSpeedLimits)-1
                        if formerSpeedLimits[i][2]<=formerSpeedLimits[end][2]
                            pop!(formerSpeedLimits)
                            break
                        end
                    end
                end
                csId=csId-1
            end
        end
    end
    =#

    if drivingCourse[end].v<characteristicSection.v_reach && drivingCourse[end].s<characteristicSection.s_end
        accelerationSection=BehaviorSection()
        accelerationSection.type="acceleration"                 # type of behavior section
        accelerationSection.s_start=drivingCourse[end].s        # first position (in m)
        accelerationSection.v_entry=drivingCourse[end].v        # entry speed (in m/s)
        push!(accelerationSection.waypoints, drivingCourse[end].i)

        currentStepSize=settings.stepSize   # initializing the step size that can be reduced near intersections
        # 08/23 : old for cycle in 1:5                    # first cycle with normal step size, second cycle with reduced step size, third cycle with more reduced step size. fourth and fith are needed in case the velocity approaches 0.0 or v_reach
        for cycle in 1:approximationLevel+1   # first cycle with normal step size followed by cycles with reduced step size depending on the level of approximation
            s_braking=max(0.0, ceil((characteristicSection.v_exit^2-drivingCourse[end].v^2)/2/train.a_braking, digits=approximationLevel))
            while drivingCourse[end].v<characteristicSection.v_reach && drivingCourse[end].s+s_braking<characteristicSection.s_end && drivingCourse[end].v>0.0       # as long as s_i + s_braking < s_CSend


                drivingCourse[end]=Waypoint(calculateForces!(drivingCourse[end], train, settings.massModel,  allCs, accelerationSection.type))

                # acceleration (in m/s^2):
                drivingCourse[end].a=(drivingCourse[end].F_T-drivingCourse[end].F_R)/train.m_union/train.ξ_union
                if drivingCourse[end].a==0.0
                    error("ERROR: a=0 m/s^2 in the acceleration phase !   with  F_T=",drivingCourse[end].F_T,"  F_Rt=",drivingCourse[end].F_Rt,"  F_Rw=",drivingCourse[end].F_Rw,"  F_Rp=",drivingCourse[end].F_Rp)
                end

                # create the next waypoint
                push!(drivingCourse, moveAStep(drivingCourse[end], settings.stepVariable, currentStepSize, characteristicSection.id))
                push!(accelerationSection.waypoints, drivingCourse[end].i)

                if length(formerSpeedLimits) > 0 # If the tail of the train is located in a former characteristic section with lower speed limit check if is is possible to accelerate as normal
                    (characteristicSection, drivingCourse, formerSpeedLimits, accelerationSection, endOfCsReached) = considerFormerSpeedLimits!(characteristicSection, drivingCourse, settings, train, allCs, formerSpeedLimits, accelerationSection)
                    if  endOfCsReached
                        return (characteristicSection, drivingCourse)
                    end
                end

                s_braking=max(0.0, ceil((characteristicSection.v_exit^2-drivingCourse[end].v^2)/2/train.a_braking, digits=approximationLevel))
            end #while

            # check which limit was reached and adjust the currentStepSize for the next cycle
            if cycle < approximationLevel+1
                if drivingCourse[end].v<=0.0
                    currentStepSize = settings.stepSize / 10.0^cycle

                elseif drivingCourse[end].s +s_braking > characteristicSection.s_end
                    currentStepSize = settings.stepSize / 10.0^cycle

                elseif drivingCourse[end].v>characteristicSection.v_reach
                    if settings.stepVariable=="v in m/s"
                        currentStepSize= characteristicSection.v_reach-drivingCourse[end-1].v
                    else
                        currentStepSize = settings.stepSize / 10.0^cycle
                    end

                elseif drivingCourse[end].s==characteristicSection.s_end
                    break

                elseif drivingCourse[end].v==characteristicSection.v_reach
                    break

                else
                    error("ERROR at acceleration until braking phase: With the step variable ",settings.stepVariable," the while loop will be left although v<v_reach and s<s_end in CS",characteristicSection.id,"  with s=" ,drivingCourse[end].s," m and v=",drivingCourse[end].v," m/s")
                end
                # delete last waypoint for recalculating the last step with reduced step size
                pop!(drivingCourse)
                pop!(accelerationSection.waypoints)

            else # if the level of approximation is reached
                if drivingCourse[end].v<=0.0
                    # push!(accelerationSection.waypoints, drivingCourse[end].i)
                    error("ERROR: The train stops during the acceleration phase in CS",characteristicSection.id," because the tractive effort is lower than the resistant forces.",
                    "       Before the stop the last point has the values s=",drivingCourse[end-1].s," m  v=",drivingCourse[end-1].v," m/s  a=",drivingCourse[end-1].a," m/s^2",
                    "       F_T=",drivingCourse[end-1].F_T," N  F_Rt=",drivingCourse[end-1].F_Rt," N  F_Rw=",drivingCourse[end-1].F_Rw," N  F_Rp=",drivingCourse[end-1].F_Rp," N.")

                elseif drivingCourse[end].v>characteristicSection.v_reach
                    pop!(drivingCourse)
                    pop!(accelerationSection.waypoints)
                elseif drivingCourse[end].s + s_braking > characteristicSection.s_end
                    pop!(drivingCourse)
                    pop!(accelerationSection.waypoints)
                else

                end
            end

            #= 08/23 +++ old
            # check which limit was reached and adjust the currentStepSize for the next cycle
            if drivingCourse[end].v<=0.0
                if cycle<3
                    currentStepSize=currentStepSize/10.0
                elseif cycle==3 || cycle==4  # new step size is calculated with interpolation
                    currentStepSize=abs((characteristicSection.v_reach-drivingCourse[end-1].v)*(drivingCourse[end].s-drivingCourse[end-1].s)/(drivingCourse[end].v-drivingCourse[end-1].v))   # step size (in m/s)
                elseif cycle==5
                    error("ERROR: The train stops during the acceleration phase in CS",characteristicSection.id," m because the tractive effort is lower than the resistant forces.",
                    "       Before the stop the last point has the values s=",drivingCourse[end-1].s,"  v=",drivingCourse[end-1].v," m/s  a=",drivingCourse[end-1].a," m/s^2",
                    "       F_T=",drivingCourse[end-1].F_T," N  F_Rt=",drivingCourse[end-1].F_Rt," N  F_Rw=",drivingCourse[end-1].F_Rw," N  F_Rp=",drivingCourse[end-1].F_Rp," N.")
                end
                pop!(drivingCourse)
                pop!(accelerationSection.waypoints)

            elseif (drivingCourse[end].s+s_braking)>characteristicSection.s_end
                if cycle<3
                    currentStepSize=currentStepSize/10.0
                    pop!(drivingCourse)
                    pop!(accelerationSection.waypoints)
                elseif cycle==3
                    ## for the intersection:
                    # correcting the step size for the last waypoint
                    v_intersection=train.a_braking*((drivingCourse[end].s-drivingCourse[end-1].s)/(drivingCourse[end].v-drivingCourse[end-1].v))+sign(drivingCourse[end].v-drivingCourse[end-1].v)*sqrt(train.a_braking^2*((drivingCourse[end].s-drivingCourse[end-1].s)/(drivingCourse[end].v-drivingCourse[end-1].v))^2-2*train.a_braking*(characteristicSection.s_end-drivingCourse[end-1].s+drivingCourse[end-1].v*((drivingCourse[end].s-drivingCourse[end-1].s)/(drivingCourse[end].v-drivingCourse[end-1].v)))+characteristicSection.v_exit^2)

                    s_intersection=characteristicSection.s_end-(characteristicSection.v_exit^2-v_intersection^2)/2/train.a_braking
                        #     s_intersection_2=(v_intersection-drivingCourse[end-1].v)*(drivingCourse[end].s-drivingCourse[end-1].s)/(drivingCourse[end].v-drivingCourse[end-1].v)+drivingCourse[end-1].s

                    drivingCourse[end].v=v_intersection
                    drivingCourse[end].s=floor(s_intersection, digits=10)                       # position (in m)  # rounded -> exact to 1 nm
                    drivingCourse[end].Δv=drivingCourse[end].v-drivingCourse[end-1].v           # step size (in m/s)
                    drivingCourse[end].Δs=drivingCourse[end].s-drivingCourse[end-1].s
                    break
                    # calculate  t, v, E
                   if settings.stepVariable=="s in m"
                       drivingCourse[end].Δt=sign(drivingCourse[end-1].a)*sqrt((drivingCourse[end-1].v/drivingCourse[end-1].a)^2+2*drivingCourse[end].Δs/drivingCourse[end-1].a)-drivingCourse[end-1].v/drivingCourse[end-1].a                         # step size (in s)
                   elseif settings.stepVariable=="v in m/s" || settings.stepVariable=="t in s"
                       drivingCourse[end].Δt=drivingCourse[end].Δv/drivingCourse[end-1].a                        # step size (in s)
                   end #if

                    drivingCourse[end].t=drivingCourse[end-1].t+drivingCourse[end].Δt                            # point in time (in s)
                    drivingCourse[end].ΔW_T=drivingCourse[end-1].F_T*drivingCourse[end].Δs                       # mechanical work in this step (in Ws)
                    drivingCourse[end].W_T=drivingCourse[end-1].W_T+drivingCourse[end].ΔW_T                      # mechanical work (in Ws)
                    drivingCourse[end].ΔE=drivingCourse[end].ΔW_T                                                # energy consumption in this step (in Ws)
                    drivingCourse[end].E=drivingCourse[end-1].E+drivingCourse[end].ΔE                            # energy consumption (in Ws)

                end #if
            elseif drivingCourse[end].v>characteristicSection.v_reach
                if settings.stepVariable=="s in m"
                    if cycle<3
                        currentStepSize=currentStepSize/10.0
                    elseif cycle==3 || cycle==4  # new step size is calculated with interpolation
                        currentStepSize=abs((characteristicSection.v_reach-drivingCourse[end-1].v)*(drivingCourse[end].s-drivingCourse[end-1].s)/(drivingCourse[end].v-drivingCourse[end-1].v))   # step size (in m/s)
                    elseif cycle==5
                    end
                    pop!(drivingCourse)
                    pop!(accelerationSection.waypoints)
                elseif settings.stepVariable=="t in s"
                        if cycle<=3
                    #    #if cycle<3
                            currentStepSize=currentStepSize/10.0
                        elseif cycle==4  # new step size is calculated with interpolation
                            currentStepSize=abs((characteristicSection.v_reach-drivingCourse[end-1].v)*(drivingCourse[end].t-drivingCourse[end-1].t)/(drivingCourse[end].v-drivingCourse[end-1].v))    # step size (in s)
                            elseif cycle==5
                        end
                        pop!(drivingCourse)
                        pop!(accelerationSection.waypoints)
                elseif settings.stepVariable=="v in m/s"
                    currentStepSize=characteristicSection.v_reach-drivingCourse[end-1].v
                    pop!(drivingCourse)
                    pop!(accelerationSection.waypoints)
                end

            elseif (drivingCourse[end].s+s_braking)==characteristicSection.s_end
                break
            elseif drivingCourse[end].v==characteristicSection.v_reach
                break
            else
                println("FEHLER: Beim Beschleunigungs-Brems-Abschnitt!")
            end #if
            =#
        end #for


        # 08/23 +++ old push!(accelerationSection.waypoints, drivingCourse[end].i)


        # calculation the accumulated acceleration section information
        accelerationSection.v_exit=drivingCourse[end].v                               # exit speed (in m/s)
        accelerationSection.s_end=drivingCourse[end].s                                # last position (in m)
        accelerationSection.s_total=accelerationSection.s_end-accelerationSection.s_start           # total length  (in m)
        accelerationSection.t_total=drivingCourse[end].t-drivingCourse[accelerationSection.waypoints[1]].t       # total running time (in s)
        accelerationSection.E_total=drivingCourse[end].E-drivingCourse[accelerationSection.waypoints[1]].E       # total energy consumption (in Ws)

        characteristicSection.v_reach=drivingCourse[end].v      # setting v_reach to the last waypoints velocity which is the highest reachable value in this characteristic section
        characteristicSection.t_total=characteristicSection.t_total+accelerationSection.t_total       # total running time (in s)
        characteristicSection.E_total=characteristicSection.E_total+accelerationSection.E_total       # total energy consumption (in Ws)

        merge!(characteristicSection.behaviorSections, Dict("acceleration"=>accelerationSection))
    end # else: just return the given waypoint number without changes due to the acceleration phase
    return (characteristicSection, drivingCourse)
end #function addAccelerationPhaseUntilBraking!


## This function calculates the waypoints of the cruising phase.
#   Therefore it gets its first waypoint and the characteristic section and returns the characteristic section including the behavior section for cruising if needed.
function addCruisingPhase!(characteristicSection::CharacteristicSection, drivingCourse::Vector{Waypoint}, s_cruising::AbstractFloat, settings::Settings, train::Train, allCs::Vector{CharacteristicSection}, cruisingType::String)
    if drivingCourse[end].v>0.0 && drivingCourse[end].v<=characteristicSection.v_reach && drivingCourse[end].s<characteristicSection.s_end
        cruisingSection=BehaviorSection()
        cruisingSection.type=cruisingType                                                       # type of behavior section
        cruisingSection.s_start=drivingCourse[end].s                                            # first position (in m)
        cruisingSection.s_end=min(drivingCourse[end].s+s_cruising, characteristicSection.s_end) # last position (in m)
        cruisingSection.v_entry=drivingCourse[end].v                                            # entry speed (in m/s)
        push!(cruisingSection.waypoints, drivingCourse[end].i)


        # traction effort and resisting forces (in N)
        drivingCourse[end]=Waypoint(calculateForces!(drivingCourse[end], train, settings.massModel,  allCs, "cruising")) # TODO: or give cruisingSection.type instead of "cruising"?

        if drivingCourse[end].F_T>=drivingCourse[end].F_R
            drivingCourse[end].a=0.0    # acceleration (in m/s^2)

            push!(drivingCourse, Waypoint())
            drivingCourse[end].i=drivingCourse[end-1].i+1   # incrementing the number of the waypoint
            push!(cruisingSection.waypoints, drivingCourse[end].i)

            # calculate s, t, v, E
            drivingCourse[end].Δs=min(s_cruising, characteristicSection.s_end-drivingCourse[end-1].s)       # step size (in m)
            drivingCourse[end].Δt=drivingCourse[end].Δs/drivingCourse[end-1].v      # step size (in s)
            drivingCourse[end].Δv=0.0                                            # step size (in m/s)
                # TODO moveAStep can not be used at the moment because of 1/a in the formulars. It has to be changed and then used with stepVariable="s in m", stepSize=min(s_cruising, characteristicSection.s_end-drivingCourse[end-1].s) -> see the three lines above

            drivingCourse[end].s=drivingCourse[end-1].s+drivingCourse[end].Δs        # position (in m)
            drivingCourse[end].t=drivingCourse[end-1].t+drivingCourse[end].Δt        # point in time (in s)
            drivingCourse[end].v=drivingCourse[end-1].v                            # velocity (in m/s)

            drivingCourse[end].ΔW_T=drivingCourse[end-1].F_T*drivingCourse[end].Δs   # mechanical work in this step (in Ws)
            drivingCourse[end].W_T=drivingCourse[end-1].W_T+drivingCourse[end].ΔW_T  # mechanical work (in Ws)
            drivingCourse[end].ΔE=drivingCourse[end].ΔW_T                          # energy consumption in this step (in Ws)
            drivingCourse[end].E=drivingCourse[end-1].E+drivingCourse[end].ΔE        # energy consumption (in Ws)


        else    # the tractive effort is lower than the resisiting forces and the train has use the highest possible effort to try to stay at v_reach
            currentStepSize=settings.stepSize

            for cycle in 1:approximationLevel+1   # first cycle with normal step size followed by cycles with reduced step size depending on the level of approximation
                while drivingCourse[end].v<=characteristicSection.v_reach && drivingCourse[end].s<characteristicSection.s_end && drivingCourse[end].v>0.0 # TODO: <= v_reach was inserted -> probably needed for homogeneous strip

                    # traction effort and resisting forces (in N)
                    drivingCourse[end]=Waypoint(calculateForces!(drivingCourse[end], train, settings.massModel,  allCs, "cruising"))

                    # acceleration (in m/s^2):
                    drivingCourse[end].a=(drivingCourse[end].F_T-drivingCourse[end].F_R)/train.m_union/train.ξ_union
                    if drivingCourse[end].a==0.0
                        # TODO: this part is important for mass stip
                    end

                    # create the next waypoint
                    push!(drivingCourse, moveAStep(drivingCourse[end], settings.stepVariable, currentStepSize, characteristicSection.id))
                    push!(cruisingSection.waypoints, drivingCourse[end].i)

                    #= TODO: the following has probably to be considered with homogeneous strip:
                    if length(formerSpeedLimits) > 0 # If the tail of the train is located in a former characteristic section with lower speed limit check if is is possible to accelerate as normal
                        (characteristicSection, drivingCourse, formerSpeedLimits, cruisingSection, endOfCsReached) = considerFormerSpeedLimits!(characteristicSection, drivingCourse, settings, train, allCs, formerSpeedLimits, accelerationSection)

                        if  endOfCsReached
                            return (characteristicSection, drivingCourse)
                        end #if
                    end #if
                    =#
                end #while

                # check which limit was reached and adjust the currentStepSize for the next cycle
                if cycle < approximationLevel+1
                    if drivingCourse[end].v<=0.0
                        currentStepSize = settings.stepSize / 10.0^cycle

                     elseif drivingCourse[end].s>characteristicSection.s_end
                        if settings.stepVariable == "s in m"
                            currentStepSize=characteristicSection.s_end-drivingCourse[end-1].s
                        else
                            currentStepSize = settings.stepSize / 10.0^cycle
                        end

                    elseif drivingCourse[end].v>characteristicSection.v_reach # copied from addAccelerationPhase. TODO is it necessary for homogeneous strip?
                        if settings.stepVariable=="v in m/s"
                            currentStepSize=characteristicSection.v_reach-drivingCourse[end-1].v
                        else
                            currentStepSize = settings.stepSize / 10.0^cycle
                        end

                    elseif drivingCourse[end].s==characteristicSection.s_end
                        break

                    #elseif drivingCourse[end].v==characteristicSection.v_reach # copied from addAccelerationPhase. TODO should it be used otherwise for homogeneous strip?
                    #    break

                    else # TODO copied from addAccelerationPhase -> probably not needed here !?
                        error("ERROR at cruising phase: With the step variable ",settings.stepVariable," the while loop will be left although v<v_reach and s<s_end in CS",characteristicSection.id,"  with s=" ,drivingCourse[end].s," m and v=",drivingCourse[end].v," m/s")
                    end
                    # delete last waypoint for recalculating the last step with reduced step size
                    pop!(drivingCourse)
                    pop!(cruisingSection.waypoints)

                else # if the level of approximation is reached
                    if drivingCourse[end].v<=0.0 # copied from addAccelerationPhase TODO: change error message?
                        error("ERROR: The train stops during the crusing phase in CS",characteristicSection.id," because the tractive effort is lower than the resistant forces.",
                        "       Before the stop the last point has the values s=",drivingCourse[end-1].s," m  v=",drivingCourse[end-1].v," m/s  a=",drivingCourse[end-1].a," m/s^2",
                        "       F_T=",drivingCourse[end-1].F_T," N  F_Rt=",drivingCourse[end-1].F_Rt," N  F_Rw=",drivingCourse[end-1].F_Rw," N  F_Rp=",drivingCourse[end-1].F_Rp," N.")
                    elseif drivingCourse[end].v>characteristicSection.v_reach # copied from addAccelerationPhase. TODO is it necessary for homogeneous strip?
                        pop!(drivingCourse)
                        pop!(cruisingSection.waypoints)
                    elseif drivingCourse[end].s>characteristicSection.s_end
                        drivingCourse[end].s=characteristicSection.s_end # rounding s down to s_end
                    else

                    end
                end
            end #for

            #=
                while drivingCourse[end].s<cruisingSection.s_end && drivingCourse[end].v>0.0
                drivingCourse[end].a=(drivingCourse[end].F_T-drivingCourse[end].F_R)/train.m_union/train.ξ_union

                # create the next waypoint
                push!(drivingCourse, moveAStep(drivingCourse[end], settings.stepVariable, currentStepSize, characteristicSection.id))
                push!(cruisingSection.waypoints, drivingCourse[end].i)

                #=
                # creating the next waypoint
                push!(drivingCourse, Waypoint())
                drivingCourse[end].i=drivingCourse[end-1].i+1         # identifier
                push!(cruisingSection.waypoints, drivingCourse[end].i)

                # calculate s, t, v, E
                if settings.stepVariable=="s in m" ||settings.stepVariable=="v in m/s"                       # instead of velocity steps distance steps are used because phase there should not be velocity steps in the cruising
                    drivingCourse[end].Δs=currentStepSize                                                    # step size (in m)
                    drivingCourse[end].Δt=sign(drivingCourse[end-1].a)*sqrt((drivingCourse[end-1].v/drivingCourse[end-1].a)^2+2*drivingCourse[end].Δs/drivingCourse[end-1].a)-drivingCourse[end-1].v/drivingCourse[end-1].a                          # step size (in s)
                    drivingCourse[end].Δv=sqrt(drivingCourse[end-1].v^2+2*drivingCourse[end].Δs*drivingCourse[end-1].a)-drivingCourse[end-1].v     # step size (in m/s)
                elseif settings.stepVariable=="t in s"                                                       # time step method
                    drivingCourse[end].Δt=currentStepSize                                                    # step size (in s)
                    drivingCourse[end].Δs=drivingCourse[end].Δt*(2*drivingCourse[end-1].v+drivingCourse[end].Δt*drivingCourse[end-1].a)/2        # step size (in m)
                    drivingCourse[end].Δv=drivingCourse[end].Δt*drivingCourse[end-1].a                          # step size (in m/s)
                end #if

                drivingCourse[end].s=drivingCourse[end-1].s+drivingCourse[end].Δs        # position (in m)
                drivingCourse[end].t=drivingCourse[end-1].t+drivingCourse[end].Δt        # point in time (in s)
                drivingCourse[end].v=drivingCourse[end-1].v+drivingCourse[end].Δv        # velocity (in m/s)

                drivingCourse[end].ΔW_T=drivingCourse[end-1].F_T*drivingCourse[end].Δs   # mechanical work in this step (in Ws)
                drivingCourse[end].W_T=drivingCourse[end-1].W_T+drivingCourse[end].ΔW_T  # mechanical work (in Ws)
                drivingCourse[end].ΔE=drivingCourse[end].ΔW_T                            # energy consumption in this step (in Ws)
                drivingCourse[end].E=drivingCourse[end-1].E+drivingCourse[end].ΔE        # energy consumption (in Ws)

                =#


                # 08/31 +++ TODO: hier lassen oder lieber hinter die Schleife?
                if drivingCourse[end].s>cruisingSection.s_end
                    if settings.stepVariable=="s in m" || settings.stepVariable=="v in m/s"   # instead of velocity steps distance steps are used because phase there should not be velocity steps in the cruising
                        currentStepSize=cruisingSection.s_end-drivingCourse[end-1].s
                    else    # if settings.stepVariable=="t in s"
                        currentStepSize=currentStepSize/10.0
                    end #if
                    pop!(drivingCourse)
                    pop!(cruisingSection.waypoints)
                elseif (cruisingSection.s_end-drivingCourse[end].s)<0.00001
                    break
                else
                    if drivingCourse[end].v<=0.0
                        if currentStepSize > settings.stepSize/10^approximationLevel
                            currentStepSize = currentStepSize/10.0
                        else

                            error("ERROR: The train stops during the cruising phase in CS",characteristicSection.id," m because the tractive effort is lower than the resistant forces.",
                            "       Before the stop the last point has the values s=",drivingCourse[end-1].s,"  v=",drivingCourse[end-1].v," m/s  a=",drivingCourse[end-1].a," m/s^2",
                            "       F_T=",drivingCourse[end-1].F_T," N  F_Rt=",drivingCourse[end-1].F_Rt," N  F_Rw=",drivingCourse[end-1].F_Rw," N  F_Rp=",drivingCourse[end-1].F_Rp," N.")
                        end
                        pop!(drivingCourse)
                        pop!(cruisingSection.waypoints)
                    end
                end
            end #while
            =#
        end

        # 08/24 old push!(cruisingSection.waypoints, drivingCourse[end].i)

        # calculation the accumulated cruising section information
        cruisingSection.v_exit=drivingCourse[end].v      # exit speed (in m/s)
        cruisingSection.s_total=cruisingSection.s_end-cruisingSection.s_start           # total length  (in m)
        cruisingSection.t_total=drivingCourse[end].t-drivingCourse[cruisingSection.waypoints[1]].t       # total running time (in s)
        cruisingSection.E_total=drivingCourse[end].E-drivingCourse[cruisingSection.waypoints[1]].E       # total energy consumption (in Ws)

        characteristicSection.t_total=characteristicSection.t_total+cruisingSection.t_total       # total running time (in s)
        characteristicSection.E_total=characteristicSection.E_total+cruisingSection.E_total       # total energy consumption (in Ws)

        merge!(characteristicSection.behaviorSections, Dict(cruisingSection.type=>cruisingSection))
    end # else: return the characteristic section without a cruising section

    return (characteristicSection, drivingCourse)
end #function addCruisingPhase!


## This function calculates the waypoints of the coasting phase.
# Therefore it gets its previous driving course and the characteristic section and returns the characteristic section and driving course including the coasting section
function addCoastingPhaseUntilBraking!(characteristicSection::CharacteristicSection, drivingCourse::Vector{Waypoint}, settings::Settings, train::Train, allCs::Vector{CharacteristicSection})
   if drivingCourse[end].v>characteristicSection.v_exit && drivingCourse[end].s<characteristicSection.s_end
       coastingSection=BehaviorSection()
       coastingSection.type="coasting"             # type of behavior section
       coastingSection.s_start=drivingCourse[end].s      # first position (in m)
       coastingSection.v_entry=drivingCourse[end].v      # entry speed (in m/s)
       push!(coastingSection.waypoints, drivingCourse[end].i)

       currentStepSize=settings.stepSize  # initializing the step size that can be reduced near intersections
       # 08/24 old for cycle in 1:3                   # first cycle with normal step size, second cycle with reduced step size, third cycle with more reduced step size
       for cycle in 1:approximationLevel+1   # first cycle with normal step size followed by cycles with reduced step size depending on the level of approximation
            s_braking=ceil((characteristicSection.v_exit^2-drivingCourse[end].v^2)/2/train.a_braking, digits=approximationLevel)
            while drivingCourse[end].v>characteristicSection.v_exit && drivingCourse[end].v<=characteristicSection.v_reach && drivingCourse[end].s + s_braking < characteristicSection.s_end # as long as s_i + s_braking < s_CSend
               # traction effort and resisting forces (in N):
               drivingCourse[end]=Waypoint(calculateForces!(drivingCourse[end], train, settings.massModel,  allCs, coastingSection.type))

               # acceleration (in m/s^2):
               drivingCourse[end].a=(drivingCourse[end].F_T-drivingCourse[end].F_R)/train.m_union/train.ξ_union

               # creating the next waypoint
               push!(drivingCourse, moveAStep(drivingCourse[end], settings.stepVariable, settings.stepSize, characteristicSection.id))
               push!(coastingSection.waypoints, drivingCourse[end].i)

               #= 08/24 old:
               # creating the next waypoint
               push!(drivingCourse, Waypoint())
               drivingCourse[end].i=drivingCourse[end-1].i+1         # identifier

               # calculate s, t, v, E
               if settings.stepVariable=="s in m"                                                           # distance step method
                   drivingCourse[end].Δs=currentStepSize                                                    # step size (in m)
                   drivingCourse[end].Δt=sign(drivingCourse[end-1].a)*sqrt((drivingCourse[end-1].v/drivingCourse[end-1].a)^2+2*drivingCourse[end].Δs/drivingCourse[end-1].a)-drivingCourse[end-1].v/drivingCourse[end-1].a                          # step size (in s)
                   drivingCourse[end].Δv=sqrt(drivingCourse[end-1].v^2+2*drivingCourse[end].Δs*drivingCourse[end-1].a)-drivingCourse[end-1].v     # step size (in m/s)
               elseif settings.stepVariable=="t in s"                                                       # time step method
                   drivingCourse[end].Δt=currentStepSize                                                    # step size (in s)
                   drivingCourse[end].Δs=drivingCourse[end].Δt*(2*drivingCourse[end-1].v+drivingCourse[end].Δt*drivingCourse[end-1].a)/2                          # step size (in m)
                   drivingCourse[end].Δv=drivingCourse[end].Δt*drivingCourse[end-1].a                          # step size (in m/s)
               elseif settings.stepVariable=="v in m/s"                                                       # velocity step method
                   drivingCourse[end].Δv=currentStepSize*sign(drivingCourse[end-1].a)                   # step size (in m/s)
                   drivingCourse[end].Δs=((drivingCourse[end-1].v+drivingCourse[end].Δv)^2-drivingCourse[end-1].v^2)/2/drivingCourse[end-1].a     # step size (in m)
                   drivingCourse[end].Δt=drivingCourse[end].Δv/drivingCourse[end-1].a                          # step size (in s)
               end #if

               drivingCourse[end].v=drivingCourse[end-1].v+drivingCourse[end].Δv                            # velocity (in m/s)
               if drivingCourse[end].v>characteristicSection.v_reach            # if the train gets to fast, it will brake
                   drivingCourse[end].v=characteristicSection.v_reach
                   drivingCourse[end].Δv=characteristicSection.v_reach-drivingCourse[end-1].v                       # step size (in m/s)
                   if drivingCourse[end].Δv==0.0
                       drivingCourse[end-1].a=0.0
                       if settings.stepVariable=="s in m" # || settings.stepVariable=="v in m/s"  ||  settings.stepVariable=="t in s"
                           drivingCourse[end].Δs=min(currentStepSize, characteristicSection.s_end-(drivingCourse[end-1].s+s_braking))
                           drivingCourse[end].Δt=drivingCourse[end].Δs/drivingCourse[end-1].v
                       elseif settings.stepVariable=="v in m/s"  ||  settings.stepVariable=="t in s"         # TODO: the coasting section is currently done with using distance steps. For example t_braking could also be used
                           drivingCourse[end].Δs=min(10, characteristicSection.s_end-(drivingCourse[end-1].s+s_braking))
                           drivingCourse[end].Δt=drivingCourse[end].Δs/drivingCourse[end-1].v
                       end
                   else
                       drivingCourse[end].Δs=((drivingCourse[end-1].v+drivingCourse[end].Δv)^2-drivingCourse[end-1].v^2)/2/drivingCourse[end-1].a     # step size (in m)
                       drivingCourse[end].Δt=drivingCourse[end].Δv/drivingCourse[end-1].a
                    end

               end
               drivingCourse[end].s=drivingCourse[end-1].s+drivingCourse[end].Δs                            # position (in m)
               drivingCourse[end].t=drivingCourse[end-1].t+drivingCourse[end].Δt                            # point in time (in s)
               drivingCourse[end].ΔW_T=drivingCourse[end-1].F_T*drivingCourse[end].Δs                       # mechanical work in this step (in Ws)
               drivingCourse[end].W_T=drivingCourse[end-1].W_T+drivingCourse[end].ΔW_T                      # mechanical work (in Ws)
               drivingCourse[end].ΔE=drivingCourse[end].ΔW_T                                                # energy consumption in this step (in Ws)
               drivingCourse[end].E=drivingCourse[end-1].E+drivingCourse[end].ΔE                            # energy consumption (in Ws)
               =#

               s_braking=ceil((characteristicSection.v_exit^2-drivingCourse[end].v^2)/2/train.a_braking)
            end # while

            # check which limit was reached and adjust the currentStepSize for the next cycle
            if cycle < approximationLevel+1
               if drivingCourse[end].s + s_braking > characteristicSection.s_end
                   currentStepSize = settings.stepSize / 10.0^cycle

               elseif drivingCourse[end].v < characteristicSection.v_exit  # TODO: if accelereation and coasting functions will be combined this case is only for coasting
                    currentStepSize = settings.stepSize / 10.0^cycle

               elseif drivingCourse[end].v > characteristicSection.v_reach
                   if settings.stepVariable=="v in m/s"
                       currentStepSize = characteristicSection.v_reach-drivingCourse[end-1].v
                   else
                       currentStepSize = settings.stepSize / 10.0^cycle
                   end
               elseif drivingCourse[end].s + s_braking == characteristicSection.s_end
                   break

               elseif drivingCourse[end].v == characteristicSection.v_exit
                   break

               else
                   # TODO: not needed. just for testing
                   error("ERROR at coasting until braking phase: With the step variable ",settings.stepVariable," the while loop will be left although v<v_reach and s+s_braking<s_end in CS",characteristicSection.id,"  with s=" ,drivingCourse[end].s," m and v=",drivingCourse[end].v," m/s")
               end
               # delete last waypoint for recalculating the last step with reduced step size
               pop!(drivingCourse)
               pop!(coastingSection.waypoints)

           else # if the level of approximation is reached
                if drivingCourse[end].v<=0.0
                    println("INFO: The train stops during the coasting phase in CS",characteristicSection.id,"                                                                ",
                    "       Before the stop the last point has the values s=",drivingCourse[end-1].s," m  v=",drivingCourse[end-1].v," m/s  a=",drivingCourse[end-1].a," m/s^2",
                    "       F_T=",drivingCourse[end-1].F_T," N  F_Rt=",drivingCourse[end-1].F_Rt," N  F_Rw=",drivingCourse[end-1].F_Rw," N  F_Rp=",drivingCourse[end-1].F_Rp," N and s_braking=",s_braking,"m.")

               elseif drivingCourse[end].s + s_braking > characteristicSection.s_end
                   # delete last waypoint becaus it went to far
                   pop!(drivingCourse)
                   pop!(coastingSection.waypoints)

               elseif drivingCourse[end].v > characteristicSection.v_reach # if the train gets to fast it has to brake  # TODO: if accelereation and coasting functions will be combined this case is different for coasting and also the order of if cases is different
                   # while coasting the train brakes to hold v_reach (only one waypoint in the end of coasting is calculated like cruising at v_reach)
                   drivingCourse[end-1].a=0.0
                   s_braking=ceil((characteristicSection.v_exit^2-drivingCourse[end-1].v^2)/2/train.a_braking)

                   # recalculate s, t, v, E
                   #drivingCourse[end].Δs= characteristicSection.s_end-drivingCourse[end-1].s - s_braking   # step size (in m)   # TODO: the coasting section is currently realised with using distance steps. For example t_braking could also be used
                   drivingCourse[end].Δs=min(currentStepSize, characteristicSection.s_end-(drivingCourse[end-1].s+s_braking))       # TODO: if settings.stepVariable=="s in m"
                   drivingCourse[end].Δt=drivingCourse[end].Δs/drivingCourse[end-1].v                      # step size (in s)
                   drivingCourse[end].Δv=0.0                                                               # step size (in m/s)

                   drivingCourse[end].s=drivingCourse[end-1].s+drivingCourse[end].Δs                       # position (in m)
                   drivingCourse[end].t=drivingCourse[end-1].t+drivingCourse[end].Δt                       # point in time (in s)
                   drivingCourse[end].v=drivingCourse[end-1].v                                             # velocity (in m/s)

                   drivingCourse[end].ΔW_T=drivingCourse[end-1].F_T*drivingCourse[end].Δs                  # mechanical work in this step (in Ws)
                                       #   =0.0
                   drivingCourse[end].W_T=drivingCourse[end-1].W_T+drivingCourse[end].ΔW_T                 # mechanical work (in Ws)
                                       #   =drivingCourse[end-1].W_T
                   drivingCourse[end].ΔE=drivingCourse[end].ΔW_T                                           # energy consumption in this step (in Ws)
                                       #   =0.0
                   drivingCourse[end].E=drivingCourse[end-1].E+drivingCourse[end].ΔE                       # energy consumption (in Ws)
                                       #   =drivingCourse[end-1].E

               else

               end
           end

           #= 08/24 old and new
           # check which limit was reached and adjust the currentStepSize for the next cycle
            if (drivingCourse[end].s+s_braking)>characteristicSection.s_end
               if cycle<3
                   currentStepSize=currentStepSize/10.0
                   pop!(drivingCourse)
                   pop!(coastingSection.waypoints) # TODO: hier soll wohl ein leeres Array gepoppt werden ..
               elseif cycle==3
                   v_intersection=train.a_braking*((drivingCourse[end].s-drivingCourse[end-1].s)/(drivingCourse[end].v-drivingCourse[end-1].v))+sign(drivingCourse[end].v-drivingCourse[end-1].v)*sqrt(train.a_braking^2*((drivingCourse[end].s-drivingCourse[end-1].s)/(drivingCourse[end].v-drivingCourse[end-1].v))^2-2*train.a_braking*(characteristicSection.s_end-drivingCourse[end-1].s+drivingCourse[end-1].v*((drivingCourse[end].s-drivingCourse[end-1].s)/(drivingCourse[end].v-drivingCourse[end-1].v)))+characteristicSection.v_exit^2)

                   s_intersection=characteristicSection.s_end-(characteristicSection.v_exit^2-v_intersection^2)/2/train.a_braking
                   # s_intersection_2=(v_intersection-drivingCourse[end-1].v)*(drivingCourse[end].s-drivingCourse[end-1].s)/(drivingCourse[end].v-drivingCourse[end-1].v)+drivingCourse[end-1].s

                   drivingCourse[end].v=v_intersection
                   drivingCourse[end].s=floor(s_intersection, digits=10)                            # position (in m)  # rounded -> exact to 1 nm
                   drivingCourse[end].Δv=drivingCourse[end].v-drivingCourse[end-1].v                # step size (in m/s)
                   drivingCourse[end].Δs=drivingCourse[end].s-drivingCourse[end-1].s


                   # calculate s, t, v, E
                   if settings.stepVariable=="s in m"
                       drivingCourse[end].Δt=sign(drivingCourse[end-1].a)*sqrt((drivingCourse[end-1].v/drivingCourse[end-1].a)^2+2*drivingCourse[end].Δs/drivingCourse[end-1].a)-drivingCourse[end-1].v/drivingCourse[end-1].a                         # step size (in s)
                   elseif settings.stepVariable=="v in m/s" || settings.stepVariable=="t in s"
                       drivingCourse[end].Δt=drivingCourse[end].Δv/drivingCourse[end-1].a                       # step size (in s)
                   end #if

                   drivingCourse[end].t=drivingCourse[end-1].t+drivingCourse[end].Δt                            # point in time (in s)
                   drivingCourse[end].ΔW_T=drivingCourse[end-1].F_T*drivingCourse[end].Δs                       # mechanical work in this step (in Ws)
                   drivingCourse[end].W_T=drivingCourse[end-1].W_T+drivingCourse[end].ΔW_T                      # mechanical work (in Ws)
                   drivingCourse[end].ΔE=drivingCourse[end].ΔW_T                                                # energy consumption in this step (in Ws)
                   drivingCourse[end].E=drivingCourse[end-1].E+drivingCourse[end].ΔE                            # energy consumption (in Ws)
               end #if
           elseif drivingCourse[end].v<characteristicSection.v_exit
               if cycle<3
                   currentStepSize=currentStepSize/10.0
                   pop!(drivingCourse)
                   pop!(coastingSection.waypoints)
               end
           elseif drivingCourse[end].v>characteristicSection.v_reach
               if drivingCourse[end].v > characteristicSection.v_reach            # if the train gets to fast it has to brake
                   if settings.stepVariable=="s in m"                                                           # distance step method
                     # TODO
                   elseif settings.stepVariable=="t in s"                                                       # time step method
                      # TODO
                   elseif settings.stepVariable=="v in m/s"                                                     # velocity step method
                       drivingCourse[end].v=characteristicSection.v_reach
                       drivingCourse[end].Δv=characteristicSection.v_reach-drivingCourse[end-1].v                       # step size (in m/s)
                       if drivingCourse[end].Δv==0.0
                           drivingCourse[end-1].a=0.0
                           if settings.stepVariable=="s in m" # || settings.stepVariable=="v in m/s"  ||  settings.stepVariable=="t in s"
                               drivingCourse[end].Δs=min(currentStepSize, characteristicSection.s_end-(drivingCourse[end-1].s+s_braking))
                               drivingCourse[end].Δt=drivingCourse[end].Δs/drivingCourse[end-1].v
                           elseif settings.stepVariable=="v in m/s"  ||  settings.stepVariable=="t in s"         # TODO: the coasting section is currently done with using distance steps. For example t_braking could also be used
                               drivingCourse[end].Δs=min(10, characteristicSection.s_end-(drivingCourse[end-1].s+s_braking))
                               drivingCourse[end].Δt=drivingCourse[end].Δs/drivingCourse[end-1].v
                           end
                       else
                           drivingCourse[end].Δs=((drivingCourse[end-1].v+drivingCourse[end].Δv)^2-drivingCourse[end-1].v^2)/2/drivingCourse[end-1].a     # step size (in m)
                           drivingCourse[end].Δt=drivingCourse[end].Δv/drivingCourse[end-1].a
                        end
                   end #if


                    drivingCourse[end].s=drivingCourse[end-1].s+drivingCourse[end].Δs                            # position (in m)
                    drivingCourse[end].t=drivingCourse[end-1].t+drivingCourse[end].Δt                            # point in time (in s)
                    drivingCourse[end].ΔW_T=drivingCourse[end-1].F_T*drivingCourse[end].Δs                       # mechanical work in this step (in Ws)
                    drivingCourse[end].W_T=drivingCourse[end-1].W_T+drivingCourse[end].ΔW_T                      # mechanical work (in Ws)
                    drivingCourse[end].ΔE=drivingCourse[end].ΔW_T                                                # energy consumption in this step (in Ws)
                    drivingCourse[end].E=drivingCourse[end-1].E+drivingCourse[end].ΔE                            # energy consumption (in Ws)
               end


               # 08/24 old println("WARNING: in the coasting phase v=",drivingCourse[end].v," gets higher than v_reach=",characteristicSection.v_reach," .   That should not happen!")
           elseif (drivingCourse[end].s+s_braking)==characteristicSection.s_end
               # there is a combination of coasting and braking for reaching characteristicSection.s_end. Coasting will stop here an braking will follow.
                break
           elseif drivingCourse[end].v==characteristicSection.v_exit
               #  characteristicSection.v_exit is reached without braking before characteristicSection.s_end is reached
                break
           else
               println("Warning: In the coasting phase of CS",characteristicSection.id," is:")
                # it is: (drivingCourse[end].s+s_braking)<=characteristicSection.s_end
                #    ans: characteristicSection.v_reach>=drivingCourse[end].v>characteristicSection.v_exit
                println("   s(",drivingCourse[end].s, ")     +    s_braking(",s_braking,")   <=   s_end(",characteristicSection.s_end,")")
                println("   v_reach(",characteristicSection.v_reach,")    >=     v(",drivingCourse[end].v,")   >     v_exit(",characteristicSection.v_exit,")")
                if cycle<3
                    currentStepSize=currentStepSize/10.0
                    pop!(drivingCourse)
                    pop!(coastingSection.waypoints)
                end
           end #if
           =#

       end #for

       # 08/24 old  push!(coastingSection.waypoints, drivingCourse[end].i)

       # calculation the accumulated coasting section information
       coastingSection.v_exit=drivingCourse[end].v                                                  # exit speed (in m/s)
       coastingSection.s_end=drivingCourse[end].s                                                   # last position (in m)
       coastingSection.s_total=coastingSection.s_end-coastingSection.s_start                        # total length  (in m)
       coastingSection.t_total=drivingCourse[end].t-drivingCourse[coastingSection.waypoints[1]].t   # total running time (in s)
       coastingSection.E_total=drivingCourse[end].E-drivingCourse[coastingSection.waypoints[1]].E   # total energy consumption (in Ws)

       characteristicSection.t_total=characteristicSection.t_total+coastingSection.t_total          # total running time (in s)
       characteristicSection.E_total=characteristicSection.E_total+coastingSection.E_total          # total energy consumption (in Ws)

       merge!(characteristicSection.behaviorSections, Dict("coasting"=>coastingSection))
   end ## else: just return the given waypoint number without changes due to the coasting phase
   return (characteristicSection, drivingCourse)
end #function addCoastingPhaseUntilBraking!

## This function calculates the waypoints of the braking phase.
#    Therefore it gets its first waypoint and the characteristic section and returns the characteristic section including the behavior section for braking if needed.
function addBrakingPhase!(characteristicSection::CharacteristicSection, drivingCourse::Vector{Waypoint}, massModel::String, train::Train, allCs::Vector{CharacteristicSection}) #, s_braking::AbstractFloat)
    if drivingCourse[end].v>characteristicSection.v_exit && drivingCourse[end].s<characteristicSection.s_end
        brakingSection=BehaviorSection()
        brakingSection.type="braking"                           # type of behavior section
        brakingSection.s_start=drivingCourse[end].s             # first position (in m)
        brakingSection.s_end=characteristicSection.s_end        # last position (in m)
        brakingSection.v_entry=drivingCourse[end].v             # entry speed (in m/s)
        push!(brakingSection.waypoints, drivingCourse[end].i)   # refering from the breaking section to the first of its waypoints

        # traction effort and resisting forces (in N)
        drivingCourse[end]=Waypoint(calculateForces!(drivingCourse[end], train, massModel,  allCs, brakingSection.type))

        push!(drivingCourse, Waypoint())
        drivingCourse[end].i=drivingCourse[end-1].i+1                       # incrementing the number of the waypoint
        push!(brakingSection.waypoints, drivingCourse[end].i)               # refering from the breaking section to the last of its waypoints

        # calculate s, t, v
        drivingCourse[end].s=brakingSection.s_end                           # position (in m)
        drivingCourse[end].v=characteristicSection.v_exit                   # velocity (in m/s)
        drivingCourse[end].Δs=drivingCourse[end].s-drivingCourse[end-1].s   # step size (in m)
        drivingCourse[end].Δv=drivingCourse[end].v-drivingCourse[end-1].v   # step size (in m/s)

        drivingCourse[end-1].a=round((drivingCourse[end].v^2-drivingCourse[end-1].v^2)/2/drivingCourse[end].Δs, digits=approximationLevel)   # acceleration (in m/s^2) (rounding because it should not be less than a_braking)
        if drivingCourse[end-1].a<train.a_braking || drivingCourse[end-1].a>=0.0
            println("Warning: a_braking gets to high in CS ",characteristicSection.id, "   with a=",drivingCourse[end-1].a  ,"  >  ",train.a_braking)
        end
        drivingCourse[end].Δt=drivingCourse[end].Δv/drivingCourse[end-1].a          # step size (in s)
        drivingCourse[end].t=drivingCourse[end-1].t+drivingCourse[end].Δt           # point in time (in s)

        drivingCourse[end].ΔW_T=0.0                                                 # mechanical work in this step (in Ws)
        drivingCourse[end].W_T=drivingCourse[end-1].W_T+drivingCourse[end].ΔW_T     # mechanical work (in Ws)
        drivingCourse[end].ΔE=drivingCourse[end].ΔW_T                               # energy consumption in this step (in Ws)
        drivingCourse[end].E=drivingCourse[end-1].E+drivingCourse[end].ΔE           # energy consumption (in Ws)

        brakingSection.v_exit=drivingCourse[end].v                                  # exit speed (in m/s)
        brakingSection.s_total=drivingCourse[end].Δs                                # total length  (in m)
        brakingSection.t_total=drivingCourse[end].Δt                                # total running time (in s)
        brakingSection.E_total=drivingCourse[end].ΔE                                # total energy consumption (in Ws)

        characteristicSection.t_total=characteristicSection.t_total+brakingSection.t_total       # total running time (in s)
        characteristicSection.E_total=characteristicSection.E_total+brakingSection.E_total       # total energy consumption (in Ws)

        merge!(characteristicSection.behaviorSections, Dict("braking"=>brakingSection))
    end  # else: return the characteristic section without a braking section
    return (characteristicSection, drivingCourse)
end #function addBrakingPhase!


end #module MovingPhases
