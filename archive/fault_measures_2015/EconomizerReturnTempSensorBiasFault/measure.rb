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
class EconomizerReturnTempSensorBiasFault < OpenStudio::Ruleset::WorkspaceUserScript

  # human readable name
  def name
    return "Economizer Return Air Temperature Sensor Bias Fault"
  end

  # human readable description
  def description
    return "This Measure simulates the effect of economizer sensor fault of any RTU to the building performance."
  end

  # human readable description of workspace approach
  def workspaceer_description
    return "To use this Measure, activate the Measure by the first boolean. Choose the Controller:OutdoorAir object to be faulted. Set the level of temperature sensor bias in degree Celcius that you want at the return air duct for the economizer during the simulation period. For example, setting 2 means the sensor is reading 28C when the actual temperature is 26C. You can also impose a schedule of the presence of fault during the simulation period. If a schedule name is not given, the model assumes that the fault is present during the entire simulation period."
  end

  # define the arguments that the user will input
  def arguments(workspace)
    args = OpenStudio::Ruleset::OSArgumentVector.new
    
    #choose the Controller:OutdoorAir to be faulted
    econ_choice = OpenStudio::Ruleset::OSArgument::makeStringArgument("econ_choice", true)
    econ_choice.setDisplayName("Enter the name of the faulted Controller:OutdoorAir object")
    # econ_choice.setDefaultValue("asintakef4058507-81d6-4711-96a3-ca67f519872c controller")  #name of economizer for the EC building
    econ_choice.setDefaultValue("")  #name of economizer for the EC building
    args << econ_choice
    
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
        runner.registerError("Measure EconomizerReturnTempSensorBiasFault cannot find "+econ_choice+". Exiting......")
        return false
      end

      # report final condition of workspace
      runner.registerFinalCondition("Imposed Sensor Bias on "+econ_choice+".")
    else
      runner.registerAsNotApplicable("EconomizerReturnTempSensorBiasFault is not running for "+econ_choice+". Skipping......")
    end

    return true

  end
  
end

# register the measure to be used by the application
EconomizerReturnTempSensorBiasFault.new.registerWithApplication
