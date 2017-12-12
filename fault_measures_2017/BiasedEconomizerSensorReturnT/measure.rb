#see the URL below for information on how to write OpenStudio measures
# http://openstudio.nrel.gov/openstudio-measure-writing-guide

#see the URL below for information on using life cycle cost objects in OpenStudio
# http://openstudio.nrel.gov/openstudio-life-cycle-examples

#see the URL below for access to C++ documentation on model objects (click on "model" in the main window to view model objects)
# https://s3.amazonaws.com/openstudio-sdk-documentation/index.html

require "#{File.dirname(__FILE__)}/resources/ScheduleSearch"
    
#define number of parameters in the model
$q_para_num = 6
$eir_para_num = 6

# start the measure
class BiasedEconomizerSensorReturnT < OpenStudio::Ruleset::WorkspaceUserScript

  # human readable name
  def name
    return "Biased Economizer Sensor: Return Temperature"
  end

  # human readable description
  def description
    return "When sensors drift and are not regularly calibrated, it causes a bias. Sensor readings often drift from their calibration with age, causing equipment control algorithms to produce outputs that deviate from their intended function. This measure simulates the biased economizer sensor (return temperature) by modifying Controller:OutdoorAir object in EnergyPlus assigned to the heating and cooling system. The fault intensity (F) for this fault is defined as the biased temperature level (K), which is also specified as one of the inputs."
  end

  # human readable description of workspace approach
  def modeler_description
    return "Three user inputs are required and, based on these user inputs, the return air temperature reading in the economizer will be replaced by the equation below, where TraF is the biased return air temperature reading, Tra is the actual return air temperature, and F is the fault intensity. TraF = Tra + F. To use this measure, choose the Controller:OutdoorAir object to be faulted. Set the level of temperature sensor bias in K that you want at the return air duct for the economizer during the simulation period. For example, setting 2 means the sensor is reading 28C when the actual temperature is 26C. You can also impose a schedule of the presence of fault during the simulation period. If a schedule name is not given, the model assumes that the fault is present during the entire simulation period."
  end

  # define the arguments that the user will input
  def arguments(workspace)
    args = OpenStudio::Ruleset::OSArgumentVector.new
    
    ##################################################
    #make choice arguments for economizers
    controlleroutdoorairs = workspace.getObjectsByType("Controller:OutdoorAir".to_IddObjectType)
    chs = OpenStudio::StringVector.new
    controlleroutdoorairs.each do |controlleroutdoorair|
      chs << controlleroutdoorair.name.to_s
    end
    econ_choice = OpenStudio::Ruleset::OSArgument::makeChoiceArgument('econ_choice', chs, true)
    econ_choice.setDisplayName("Choice of economizers.")
    econ_choice.setDefaultValue(chs[0].to_s)
    args << econ_choice
    ##################################################
    
    #name of schedule for the presence of fault at the return air sensor. 0 for no fault and 1.0 means fault level.
    ret_tmp_sch = OpenStudio::Ruleset::OSArgument::makeStringArgument("ret_tmp_sch", true)
    ret_tmp_sch.setDisplayName("Enter the name of the schedule of the fault presence at the return air temperature sensor. 0 means no fault and 1 means faulted. If you do not have a schedule, leave this blank.")
    ret_tmp_sch.setDefaultValue("")
    args << ret_tmp_sch
	
    #make a double argument for the temperature sensor bias
    ret_tmp_bias = OpenStudio::Ruleset::OSArgument::makeDoubleArgument("ret_tmp_bias", false)
    ret_tmp_bias.setDisplayName("Enter the bias level of the return air temperature sensor. A positive number means that the sensor is reading a temperature higher than the true temperature. (K)")
    ret_tmp_bias.setDefaultValue(-2)  #default fouling level to be 30%
    args << ret_tmp_bias
    
    #name of schedule for the multiplier of fault level at the return air sensor.
    ret_bias_sch = OpenStudio::Ruleset::OSArgument::makeStringArgument("ret_bias_sch", true)
    ret_bias_sch.setDisplayName("Enter the name of the schedule for the multiplier of bias if you want to simulate a change of return air temperature sensor bias  during simulation period. 0 means no fault and 2 means that the bias at that time is doubled. If you do not need this function, leave this blank.")
    ret_bias_sch.setDefaultValue("")
    args << ret_bias_sch

    return args
  end

  # define what happens when the measure is run
  def run(workspace, runner, user_arguments)
    super(workspace, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(workspace), user_arguments)
      return false
    end
    
    #obtain values
    econ_choice = runner.getStringArgumentValue('econ_choice',user_arguments)
    ret_tmp_sch = runner.getStringArgumentValue('ret_tmp_sch',user_arguments)
    ret_tmp_bias = runner.getDoubleArgumentValue('ret_tmp_bias',user_arguments)
    ret_bias_sch = runner.getStringArgumentValue('ret_bias_sch',user_arguments)
    
    if ret_tmp_bias != 0 # only continue if the user is running the module and the readings are sensible
    
      runner.registerInitialCondition("Imposing Sensor Bias on "+econ_choice+".")
      
      #read data for scheduletypelimits
      scheduletypelimits = workspace.getObjectsByType("ScheduleTypeLimits".to_IddObjectType)
      
      #if user-defined schedules are used, check if the schedules exist
      usr_sch_choices = [ret_tmp_sch, ret_bias_sch, ret_tmp_sch, ret_bias_sch]
      usr_scheduletypelimits = []
      usr_schedule_code = []
      usr_sch_choices.each do |sch_choice|
        if not sch_choice.eql?("")
        
          #check if the schedule exists
          bool_schedule, schedule_type_limit, schedule_code = schedule_search(workspace, sch_choice)
          usr_scheduletypelimits << schedule_type_limit
          usr_schedule_code << schedule_code
          
          if not bool_schedule
            runner.registerError("User-defined schedule "+sch_choice+" does not exist. Exiting......")
            return false
          end
        else
          usr_scheduletypelimits << ""
          usr_schedule_code << ""          
        end        
      end
    
      #find the RTU to change
      no_econ_found = true
      controlleroutdoorairs = workspace.getObjectsByType("Controller:OutdoorAir".to_IddObjectType)
      controlleroutdoorairs.each do |controlleroutdoorair|
        if controlleroutdoorair.getString(0).to_s.eql?(econ_choice)
          no_econ_found = false
          
          #create an empty string_objects to be appended into the .idf file
          string_objects = []
          
          #append FaultModel objects to the idf file
          
          #return air sensor temperature bias
          if ret_tmp_bias != 0
            string_objects << "
              FaultModel:TemperatureSensorOffset:ReturnAir,
                "+econ_choice+"RETTempSensorFault, !- Name
                "+ret_tmp_sch+", !- Availability Schedule Name
                "+ret_bias_sch+", !- Severity Schedule Name
                Controller:OutdoorAir, !- Controller Object Type
                "+econ_choice+", !- Controller Object Name
                #{ret_tmp_bias}, !- Temperature Sensor Offset
            "
          end
          
          #add all of the strings to workspace to create IDF objects
          string_objects.each do |string_object|
            idfObject = OpenStudio::IdfObject::load(string_object)
            object = idfObject.get
            wsObject = workspace.addObject(object)
          end
            
        end
      end
      
      #give an error for the name if no RTU is changed
      if no_econ_found
        runner.registerError("Measure BiasedEconomizerSensorReturnT cannot find "+econ_choice+". Exiting......")
        return false
      end

      # report final condition of workspace
      runner.registerFinalCondition("Imposed Sensor Bias on "+econ_choice+".")
    else
      runner.registerAsNotApplicable("BiasedEconomizerSensorReturnT is not running for "+econ_choice+". Skipping......")
    end

    return true

  end
  
end

# register the measure to be used by the application
BiasedEconomizerSensorReturnT.new.registerWithApplication
