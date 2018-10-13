package treatments
{
	import com.adobe.utils.DateUtil;
	import com.spikeapp.spike.airlibrary.SpikeANE;
	
	import flash.events.EventDispatcher;
	import flash.system.System;
	import flash.text.SoftKeyboardType;
	import flash.utils.Dictionary;
	
	import database.BgReading;
	import database.CGMBlueToothDevice;
	import database.Calibration;
	import database.CommonSettings;
	import database.Database;
	import database.Sensor;
	
	import events.CalibrationServiceEvent;
	import events.SettingsServiceEvent;
	import events.TreatmentsEvent;
	
	import feathers.controls.Button;
	import feathers.controls.Callout;
	import feathers.controls.DateTimeSpinner;
	import feathers.controls.Label;
	import feathers.controls.LayoutGroup;
	import feathers.controls.NumericStepper;
	import feathers.controls.PickerList;
	import feathers.controls.Radio;
	import feathers.controls.ScrollBarDisplayMode;
	import feathers.controls.ScrollContainer;
	import feathers.controls.ScrollPolicy;
	import feathers.controls.TextInput;
	import feathers.controls.popups.DropDownPopUpContentManager;
	import feathers.controls.renderers.DefaultListItemRenderer;
	import feathers.controls.renderers.IListItemRenderer;
	import feathers.core.ToggleGroup;
	import feathers.data.ArrayCollection;
	import feathers.events.FeathersEventType;
	import feathers.layout.Direction;
	import feathers.layout.HorizontalAlign;
	import feathers.layout.HorizontalLayout;
	import feathers.layout.TiledRowsLayout;
	import feathers.layout.VerticalAlign;
	import feathers.layout.VerticalLayout;
	
	import model.ModelLocator;
	
	import services.CalibrationService;
	import services.NightscoutService;
	
	import starling.animation.Transitions;
	import starling.animation.Tween;
	import starling.core.Starling;
	import starling.display.Sprite;
	import starling.events.Event;
	
	import treatments.food.Food;
	import treatments.food.ui.FoodManager;
	
	import ui.AppInterface;
	import ui.popups.AlertManager;
	import ui.screens.Screens;
	import ui.screens.display.LayoutFactory;
	
	import utils.Constants;
	import utils.DeviceInfo;
	import utils.TimeSpan;
	import utils.Trace;
	import utils.UniqueId;
	
	[ResourceBundle("treatments")]
	[ResourceBundle("globaltranslations")]

	public class TreatmentsManager extends EventDispatcher
	{
		/* Instance */
		private static var _instance:TreatmentsManager = new TreatmentsManager();
		
		/* Internal objects */
		public static var treatmentsList:Array = [];
		public static var treatmentsMap:Dictionary = new Dictionary();
		
		/* Internal Properties */
		private static const MAX_IOB_COB_CACHED_ITEMS:int = 30;
		public static var pumpIOB:Number = 0;
		public static var pumpCOB:Number = 0;
		public static var nightscoutTreatmentsLastModifiedHeader:String = "";
		private static var foodManager:FoodManager;
		private static var IOBCache:Array = [];
		private static var COBCache:Array = [];

		//Treatments callout display objects
		private static var treatmentInserterContainer:LayoutGroup;
		private static var treatmentInserterTitleLabel:Label;
		private static var insulinTextInput:TextInput;
		private static var insulinSpacer:Sprite;
		private static var glucoseTextInput:TextInput;
		private static var glucoseSpacer:Sprite;
		private static var carbsTextInput:TextInput;
		private static var carbSpacer:Sprite;
		private static var noteSpacer:Sprite;
		private static var treatmentTime:DateTimeSpinner;
		private static var treatmentSpacer:Sprite;
		private static var otherFieldsContainer:LayoutGroup;
		private static var insulinList:PickerList;
		private static var createInsulinButton:Button;
		private static var notes:TextInput;
		private static var actionContainer:LayoutGroup;
		private static var cancelButton:Button;
		private static var addButton:Button;
		private static var calloutPositionHelper:Sprite;
		private static var treatmentCallout:Callout;
		private static var extendedCarbContainer:LayoutGroup;
		private static var carbOffSet:NumericStepper;
		private static var carbOffsetSuffix:Label;
		private static var carbDelayContainer:LayoutGroup;
		private static var fastCarb:Radio;
		private static var mediumCarb:Radio;
		private static var slowCarb:Radio;
		private static var carbDelayGroup:ToggleGroup;
		private static var foodManagerButton:Button;
		private static var foodManagerContainer:LayoutGroup;
		private static var totalScrollContainer:ScrollContainer;
		private static var contentScrollContainer:ScrollContainer;
		
		public function TreatmentsManager()
		{
			if (_instance != null)
				throw new Error("TreatmentsManager is not meant to be instantiated!");
		}
		
		public static function init():void
		{
			Trace.myTrace("TreatmentsManager.as", "init called!");
			
			//Event Listeners
			CalibrationService.instance.addEventListener(CalibrationServiceEvent.INITIAL_CALIBRATION_EVENT, onCalibrationReceived);
			CalibrationService.instance.addEventListener(CalibrationServiceEvent.NEW_CALIBRATION_EVENT, onCalibrationReceived);
			CommonSettings.instance.addEventListener(SettingsServiceEvent.SETTING_CHANGED, onSettingChanged);
			
			//Fetch Data From Database
			fetchAllTreatmentsFromDatabase();
		}
		
		public static function fetchAllTreatmentsFromDatabase():void
		{
			if (!CGMBlueToothDevice.isFollower() || ModelLocator.INTERNAL_TESTING)
			{
				Trace.myTrace("TreatmentsManager.as", "Fetching treatments from database...");
				
				var now:Number = new Date().valueOf();
				treatmentsList.length = 0;
				var dbTreatments:Array = Database.getTreatmentsSynchronous(now - TimeSpan.TIME_24_HOURS, now);
				
				if (dbTreatments != null && dbTreatments.length > 0)
				{
					for (var i:int = 0; i < dbTreatments.length; i++) 
					{
						var dbTreatment:Object = dbTreatments[i] as Object;
						if (dbTreatment == null)
							continue;
						
						var treatment:Treatment = new Treatment
							(
								dbTreatment.type,
								dbTreatment.lastmodifiedtimestamp,
								dbTreatment.insulinamount,
								dbTreatment.insulinid,
								dbTreatment.carbs,
								dbTreatment.glucose,
								dbTreatment.glucoseestimated,
								dbTreatment.note,
								null,
								dbTreatment.carbdelay,
								dbTreatment.basalduration
							);
						treatment.ID = dbTreatment.id;
						
						treatmentsList.push(treatment);
						treatmentsMap[treatment.ID] = treatment;
						
						//Sort Treatments
						treatmentsList.sortOn(["timestamp"], Array.NUMERIC);
					}
				}
				
				Trace.myTrace("TreatmentsManager.as", "Fetched " + treatmentsList.length + " treatment(s)");
			}
		}
		
		private static function onSettingChanged(e:SettingsServiceEvent):void
		{
			if (e.data == CommonSettings.COMMON_SETTING_CURRENT_SENSOR && Sensor.getActiveSensor() != null && !NightscoutService.serviceActive )
			{
				addInternalSensorStartTreatment(Sensor.getActiveSensor().startedAt, UniqueId.createEventId());
			}
		}
		
		private static function onCalibrationReceived(e:CalibrationServiceEvent):void 
		{
			//Ensures compatibility with the new method of only one initial calibration
			if (Calibration.allForSensor().length == 1) 
				return;
			
			//No need to do anything. Nightscout service will take care of it
			if (NightscoutService.serviceActive) 
				return;
			
			Trace.myTrace("TreatmentsManager.as", "onCalibrationReceived called! Creating new calibration treatment.");
			
			//Add calibration treatment to Spike
			var lastCalibration:Calibration = Calibration.last();
			TreatmentsManager.addInternalCalibrationTreatment(lastCalibration.bg, lastCalibration.timestamp, lastCalibration.uniqueId);
		}
		
		public static function getTotalIOB(time:Number):IOBCalcTotals
		{
			//Check cache
			var numberOfCachedItems:int = IOBCache.length;
			var numberOfTreatmentsItems:int = treatmentsList.length;
			
			if (numberOfCachedItems > MAX_IOB_COB_CACHED_ITEMS)
			{
				IOBCache = IOBCache.slice(-MAX_IOB_COB_CACHED_ITEMS); //If number of cached items is bigger than MAX_CACHED_ITEMS we truncate the array removing the older entries.
				numberOfCachedItems = MAX_IOB_COB_CACHED_ITEMS;
			}
			
			for(var i:int = numberOfCachedItems - 1 ; i >= 0; i--)
			{
				var cachedItem:Object = IOBCache[i];
				if (Math.abs(cachedItem.timestamp - time) < TimeSpan.TIME_1_MINUTE && cachedItem.numTreatments == numberOfTreatmentsItems)
				{
					return cachedItem.iobCalc;
				}
			}
			
			//var algorithm:String = "nightscout";
			var algorithm:String = "openaps";
			
			var result:IOBCalcTotals;
			
			if (algorithm == "nightscout")
			{
				//Get calculations
				result = getTotalIOBNightscout(time);
				
				//Cache them
				IOBCache.push( {timestamp: time, numTreatments: numberOfTreatmentsItems, iobCalc: result } );
				
				//Return them
				return result;
			}
			else if (algorithm == "openaps")
			{
				//Get calculations
				result = getTotalIOBOpenAPS(time, "bilinear");
				
				//Cache them
				IOBCache.push( {timestamp: time, numTreatments: numberOfTreatmentsItems, iobCalc: result } );
				
				//Return them
				return result;
			}
			
			//Get calculations
			result = getTotalIOBNightscout(time); //Defaults to Nightscout if everything else fails
			
			//Cache them
			IOBCache.push( {timestamp: time, numTreatments: numberOfTreatmentsItems, iobCalc: result } );
			
			//Return them
			return result;
		}
		
		public static function getTotalIOBNightscout(time:Number):IOBCalcTotals
		{
			//OpenAPS/Loop Nightscout Support. Return value fetched from NS.
			if (CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_TREATMENTS_LOOP_OPENAPS_USER_ENABLED) == "true")
			{
				return new IOBCalcTotals(time, 0, pumpIOB, pumpIOB, Number.NaN, Number.NaN);
			}
			
			var totalIOB:Number = 0;
			var totalActivity:Number = 0;
			var bolusInsulin:Number = 0;
			var firstInsulinTreatmentTime:Number = time;
			
			if (treatmentsList != null && treatmentsList.length > 0)
			{
				var loopLength:int = treatmentsList.length;
				for (var i:int = 0; i < loopLength; i++) 
				{
					var treatment:Treatment = treatmentsList[i];
					if (treatment != null && treatment.insulinAmount > 0)
					{
						var treatmentIOBCalc:IOBCalc = treatment.calculateIOBNightscout(time);
						totalIOB += treatmentIOBCalc.iobContrib;
						totalActivity += treatmentIOBCalc.activityContrib;
						if (treatmentIOBCalc.iobContrib > 0)
						{
							bolusInsulin += treatment.insulinAmount;
							
							if (treatment.timestamp < firstInsulinTreatmentTime)
							{
								firstInsulinTreatmentTime = treatment.timestamp;
							}
						}
					}
				}
			}
			
			totalIOB = isNaN(totalIOB) ? 0 : Math.floor(totalIOB * 100) / 100;
			
			var results:IOBCalcTotals = new IOBCalcTotals
				(
					time,
					totalActivity,
					totalIOB,
					totalIOB,
					bolusInsulin,
					firstInsulinTreatmentTime
				);
			
			return results;
		}
		
		public static function getTotalIOBOpenAPS(time:Number, curve:String):IOBCalcTotals
		{
			//OpenAPS/Loop Nightscout Support. Return value fetched from NS.
			if (CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_TREATMENTS_LOOP_OPENAPS_USER_ENABLED) == "true")
			{
				return new IOBCalcTotals(time, 0, pumpIOB, pumpIOB, Number.NaN, Number.NaN);
			}
			
			var now:Number = time;
			var profile:Profile = ProfileManager.getProfileByTime(now);
			var dia:Number = 3; //We set a default DIA of 3 but this will be overriden by each individual DIA
			var peak:Number = 0;
			var iob:Number = 0;
			var bolusiob:Number = 0;
			var bolusinsulin:Number = 0;
			var activity:Number = 0;
			var firstInsulinTreatmentTime:Number = time;
			
			var curveDefaults:Object = {};
			curveDefaults["bilinear"] = 
			{
				requireLongDia: false,
				peak: 75 // not really used, but prevents having to check later
			};
			curveDefaults["rapid-acting"] = 
			{
				requireLongDia: true,
				peak: 75,
				tdMin: 300
			};
			curveDefaults["ultra-rapid"] = 
			{
				requireLongDia: true,
				peak: 55,
				tdMin: 300
			};
			
			if (profile.insulinCurve != "")
				curve = profile.insulinCurve.toLowerCase();
			
			if (!(curve in curveDefaults))
			{
				Trace.myTrace("TreatmentsManager.as", 'Unsupported curve function: "' + curve + '". Supported curves: "bilinear", "rapid-acting" (Novolog, Novorapid, Humalog, Apidra) and "ultra-rapid" (Fiasp). Defaulting to "rapid-acting".');
				curve = 'rapid-acting';
			}
			
			var defaults:Object = curveDefaults[curve];
			
			peak = defaults.peak;
			
			var numberOfTreatments:int = treatmentsList.length;
			for (var i:int = 0; i < numberOfTreatments; i++) 
			{
				var treatment:Treatment = treatmentsList[i];
				
				if (treatment.timestamp < now && treatment.insulinAmount > 0) //Check if treatment is valid and contains insulin otherwise skip it.
				{
					dia = treatment.dia;
					/*if (defaults.requireLongDia && dia < 5) 
					{
						// Force minimum of 5 hour DIA when default requires a Long DIA.
						//Trace.myTrace("TreatmentsManager.as", "Insulin curve requires DIA of 5 hours or more with the new curves. Current DIA is: " + dia + ".  Defaulting to 5 hours.");
						dia = 5;
					}*/
					
					var dia_ago:Number = now - (dia * 60 * 60 * 1000);
					
					if (treatment.timestamp > dia_ago)
					{
						var tIOB:IOBCalc = treatment.calculateIOBOpenAPS(time, curve, dia, peak, profile);
						
						if (tIOB != null)
						{
							if (!isNaN(tIOB.iobContrib))
							{
								iob += tIOB.iobContrib;
								bolusiob += tIOB.iobContrib;
								bolusinsulin += treatment.insulinAmount;
								
								if (tIOB.iobContrib > 0 && treatment.timestamp < firstInsulinTreatmentTime)
								{
									firstInsulinTreatmentTime = treatment.timestamp;
								}
							}
							
							if (!isNaN(tIOB.activityContrib))
							{
								activity += tIOB.activityContrib;
							}
							
							if (!isNaN(tIOB.iobContrib)) 
							{
								bolusiob += tIOB.iobContrib;
								bolusinsulin += treatment.insulinAmount;
							}
						}
					}
				}
			}
			
			var results:IOBCalcTotals = new IOBCalcTotals
			(
				time,
				Math.round(activity * 10000) / 10000,
				Math.round(iob * 1000) / 1000,
				Math.round(bolusiob * 1000) / 1000,
				Math.round(bolusinsulin * 1000) / 1000,
				firstInsulinTreatmentTime
			);
			
			return results;
		}
		
		public static function setPumpIOB(value:Number):void
		{
			if (isNaN(value))
				value = 0;
			
			pumpIOB = value;
		}
		
		public static function notifyIOBCOB():void
		{
			_instance.dispatchEvent(new TreatmentsEvent(TreatmentsEvent.IOB_COB_UPDATED));
		}
		
		public static function getTotalCOB(time:Number):CobCalcTotals 
		{
			//Check cache
			var numberOfCachedItems:int = COBCache.length;
			var numberOfTreatmentItems:int = treatmentsList.length;
			
			if (numberOfCachedItems > MAX_IOB_COB_CACHED_ITEMS)
			{
				COBCache = COBCache.slice(-MAX_IOB_COB_CACHED_ITEMS); //If number of cached items is bigger than MAX_CACHED_ITEMS we truncate the array removing the older entries.
				numberOfCachedItems = MAX_IOB_COB_CACHED_ITEMS;
			}
			
			for(var i:int = numberOfCachedItems - 1 ; i >= 0; i--)
			{
				var cachedItem:Object = COBCache[i];
				if (Math.abs(cachedItem.timestamp - time) < TimeSpan.TIME_1_MINUTE && cachedItem.numTreatments == numberOfTreatmentItems)
				{
					return cachedItem.cobCalc;
				}
			}
			
			//No cached data found. Perform real calculations
			var algorith:String = "openaps";
			var result:CobCalcTotals;
			
			if (algorith == "nightscout")
			{
				//Get calculations
				result = getTotalCOBNightscout(time);
				
				//Cache them
				COBCache.push( {timestamp: time, numTreatments: numberOfTreatmentItems, cobCalc: result } );
				
				//Return them
				return result;
			}
			else if (algorith == "openaps")
			{
				//Get calculations
				result = getTotalCOBOpenAPS(time);
				
				//Cache them
				COBCache.push( {timestamp: time, numTreatments: numberOfTreatmentItems, cobCalc: result } );
				
				//Return them
				return result;
			}
			
			//Get calculations
			result = getTotalCOBNightscout(time); //If everything else we default to Nightscout
			
			//Cache them
			COBCache.push( {timestamp: time, numTreatments: numberOfTreatmentItems, cobCalc: result } );
			
			//Return them
			return result;
		}
		
		public static function getTotalCOBNightscout(time:Number):CobCalcTotals
		{
			//OpenAPS/Loop Support. Return value fetched from NS.
			if (CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_TREATMENTS_LOOP_OPENAPS_USER_ENABLED) == "true")
			{
				return new CobCalcTotals
				(
					time,
					pumpCOB
				);
			}
			
			var carbsAbsorptionRate:Number = ProfileManager.getCarbAbsorptionRate();
			
			// TODO: figure out the liverSensRatio that gives the most accurate purple line predictions
			var liverSensRatio:int = 8;
			var totalCOB:Number = 0;
			var isDecaying:Number = 0;
			var lastDecayedBy:Number = 0;
			var lastCarbTime:Number = time;
			var activeCarbs:Number = 0;
			var firstCarbTime:Number = time;
			
			if (treatmentsList != null && treatmentsList.length > 0)
			{
				var currentProfile:Profile = ProfileManager.getProfileByTime(time);
				var isf:Number = Number(currentProfile.insulinSensitivityFactors);
				var ic:Number = Number(currentProfile.insulinToCarbRatios);
				
				//Sort Treatments
				treatmentsList.sortOn(["timestamp"], Array.NUMERIC);
				
				var loopLength:int = treatmentsList.length;
				for (var i:int = 0; i < loopLength; i++) 
				{
					var treatment:Treatment = treatmentsList[i];
					if (treatment != null && treatment.carbs > 0 && time >= treatment.timestamp)
					{
						var cCalc:CobCalc = treatment.calculateCOB(lastDecayedBy, time);
						if (cCalc != null)
						{
							var decaysin_hr:Number = (cCalc.decayedBy - time) / 1000 / 60 / 60;
							
							if (decaysin_hr > -10 && !isNaN(isf)) 
							{
								var actStart:Number = 0;
								if (true)//(lastDecayedBy != 0)
								{
									actStart = getTotalIOB(lastDecayedBy).activity;
								}
								
								var actEnd:Number = getTotalIOB(cCalc.decayedBy).activity;
								
								var avgActivity:Number = (actStart + actEnd) / 2;
								var delayedCarbs:Number = ( avgActivity *  liverSensRatio / isf ) * ic;
								var delayMinutes:Number = Math.round(delayedCarbs / carbsAbsorptionRate * 60);
								
								if (delayMinutes > 0) 
								{
									cCalc.decayedBy += (delayMinutes * 60 * 1000);
									decaysin_hr = (cCalc.decayedBy - time) / 1000 / 60 / 60;
								}
							}
							
							lastDecayedBy = cCalc.decayedBy;
							
							if (decaysin_hr > 0) 
							{
								var treatmentCOB:Number = Math.min(Number(treatment.carbs), decaysin_hr * carbsAbsorptionRate);
								if (isNaN(treatmentCOB))
									treatmentCOB = 0;
								totalCOB += treatmentCOB;
								isDecaying = cCalc.isDecaying;
								
								if (treatmentCOB > 0)
								{
									lastCarbTime = treatment.timestamp;
									activeCarbs = treatment.carbs;
									
									if (treatment.timestamp < firstCarbTime)
									{
										firstCarbTime = treatment.timestamp;
									}
								}
							} 
							else 
								totalCOB += 0;
						}
						else
							totalCOB += 0;
					}
				}
			}
			
			if (totalCOB < 0 || isNaN(totalCOB))
				totalCOB = 0;
			else
				totalCOB = Math.round(totalCOB * 10) / 10;
			
			var results:CobCalcTotals = new CobCalcTotals
				(
					time,
					totalCOB,
					activeCarbs,
					lastCarbTime,
					firstCarbTime,
					activeCarbs - totalCOB
				);
			
			return results;
		}
		
		public static function getTotalCOBOpenAPS(time:Number):CobCalcTotals
		{
			//Sort Treatments
			treatmentsList.sortOn(["timestamp"], Array.NUMERIC);
			var openAPSTreatmentsList:Array = treatmentsList.concat().reverse();
			
			var currentProfile:Profile = ProfileManager.getProfileByTime(time);
			
			var carbs:Number = 0;
			var nsCarbs:Number = 0;
			var bwCarbs:Number = 0;
			var journalCarbs:Number = 0;
			var bwFound :Boolean= false;
			var carbDelay:Number = 20 * 60 * 1000; //Need to overwrite this to the individual carb delay.
			var maxCarbs:Number = 0;
			var mealCarbTime:Number = time;
			var lastCarbTime:Number = 0;
			var firstActiveCarbTreatmentTime:Number = time;
			var i:int = 0
			
			var iob_inputs:Object = 
			{
				profile: currentProfile,
				history: openAPSTreatmentsList
			};
			
			// We make a copy of all readings and remove the ones that arrived after the desired COB time.
			// This makes the OpenAPS COB algorithm compatible with retro values.
			// If then reverse the array so the last reading comes first. This is to make it compatible with how OpenAPS expects the data to be fed.
			var availableReadings:Array = ModelLocator.bgReadings.concat();
			for(i = availableReadings.length - 1 ; i >= 0; i--)
			{
				var readingCandidate:BgReading = availableReadings[i];
				if (readingCandidate != null)
				{
					if (readingCandidate.timestamp > time)
					{
						availableReadings.pop();
					}
					else
						break;
				}
			}
			availableReadings.reverse();
			
			var COB_inputs:Object = 
			{
				glucose_data: availableReadings,
				iob_inputs: iob_inputs,
				mealTime: mealCarbTime
			};
			
			var mealCOB:Number = 0;
			var carbsToRemove:Number = 0;
			var carbsAbsorbed:Number = 0;
			
			var numberOfTreatments:int = openAPSTreatmentsList.length;
			for (i = 0; i < numberOfTreatments; i++) 
			{
				var treatment:Treatment = openAPSTreatmentsList[i];
				var now:Number = time;
				
				// consider carbs from up to 6 hours ago in calculating COB
				var carbWindow:Number = now - (6 * 60 * 60 * 1000);
				var treatmentTime:Number = treatment.timestamp;
				
				if (treatmentTime > carbWindow && treatmentTime <= now) 
				{
					if (treatment.carbs > 0) 
					{
						carbs += treatment.carbs;
						COB_inputs.mealTime = treatmentTime;
						lastCarbTime = Math.max(lastCarbTime, treatmentTime);
						
						var myCarbsAbsorbed:Number = calcMealCOB(COB_inputs).carbsAbsorbed;
						carbsAbsorbed += myCarbsAbsorbed;
						var myMealCOB:Number = Math.max(0, carbs - myCarbsAbsorbed);
						
						if (!isNaN(myMealCOB))
						{
							mealCOB = Math.max(mealCOB, myMealCOB);
							
							if (myMealCOB > 0 && treatment.timestamp < firstActiveCarbTreatmentTime)
							{
								firstActiveCarbTreatmentTime = treatment.timestamp;
							}
								
						}
						else
						{
							trace("Bad myMealCOB:",myMealCOB, "mealCOB:",mealCOB, "carbs:",carbs,"myCarbsAbsorbed:",myCarbsAbsorbed);
						}
						
						if (myMealCOB < mealCOB) 
						{
							carbsToRemove += treatment.carbs;
						} 
						else 
						{
							carbsToRemove = 0;
						}
					}
				}
			}
			
			// only include carbs actually used in calculating COB
			carbs -= carbsToRemove;
			
			// calculate the current deviation and steepest deviation downslope over the last hour
			COB_inputs.ciTime = time;
			
			// set mealTime to 6h ago for Deviation calculations
			COB_inputs.mealTime = time - (6 * 60 * 60 * 1000);
			var c:Object = calcMealCOB(COB_inputs);
			
			// if currentDeviation is null or maxDeviation is 0, set mealCOB to 0 for zombie-carb safety
			if (c.currentDeviation == null || isNaN(c.currentDeviation)) 
			{
				trace("Warning: setting mealCOB to 0 because currentDeviation is null/undefined");
				mealCOB = 0;
			}
			
			if (c.maxDeviation == null || isNaN(c.maxDeviation)) 
			{
				trace("Warning: setting mealCOB to 0 because maxDeviation is 0 or undefined");
				mealCOB = 0;
			}
			
			var results:CobCalcTotals = new CobCalcTotals
				(
					time,
					Math.round(mealCOB * 10) / 10,
					Math.round( carbs * 1000 ) / 1000,
					lastCarbTime,
					firstActiveCarbTreatmentTime,
					carbsAbsorbed,
					Math.round( c.currentDeviation * 100 ) / 100,
					Math.round( c.maxDeviation * 100 ) / 100,
					Math.round( c.minDeviation * 100 ) / 100,
					Math.round( c.slopeFromMaxDeviation * 1000 ) / 1000,
					Math.round( c.slopeFromMinDeviation * 1000 ) / 1000
				);
			
			return results;
		}
		
		private static function calcMealCOB(inputs:Object):Object
		{
			var glucose_data:Array = inputs.glucose_data;
			var iob_inputs:Object = inputs.iob_inputs; //Should hold history (treatments) and current profile
			var profile:Profile = inputs.iob_inputs.profile;
			var mealTime:Number = inputs.mealTime;
			var ciTime:Number = inputs.ciTime != null ? inputs.ciTime : Number.NaN;
			
			var avgDeltas:Array = [];
			var bgis:Array = [];
			var deviations:Array = [];
			var deviationSum:Number = 0;
			var carbsAbsorbed:Number = 0;
			var bucketed_data:Array = [];
			bucketed_data[0] = { glucose: glucose_data[0].calculatedValue, timestamp: glucose_data[0].timestamp, date: glucose_data[0].timestamp };
			
			var j:Number = 0;
			var foundPreMealBG:Boolean = false;
			var lastbgi:Number = 0;
			var i:int;
			
			if (bucketed_data[0] == null || isNaN(bucketed_data[0].glucose) || bucketed_data[0].glucose < 39) 
			{
				lastbgi = -1;
			}
			
			var bgTime:Number;
			
			var glucoseDataLength:int = glucose_data.length;
			for (i = 1; i < glucoseDataLength; ++i)
			{
				var bgReading:BgReading = glucose_data[i];
				var bgCalculatedValue:Number = bgReading.calculatedValue;
				var spikeBgTime:Number = bgReading.timestamp;
				var lastbgTime:Number;
				
				if (bgReading == null)
					continue;
				
				bgTime = spikeBgTime;
				
				if (bgCalculatedValue < 39) 
				{
					// Skip reading
					continue;
				}
				
				// only consider BGs for 6h after a meal for calculating COB
				var hoursAfterMeal:Number = (bgTime - mealTime) / (60 * 60 * 1000);
				if (hoursAfterMeal > 6)
				{
					continue;
				} 
				else if (foundPreMealBG)
				{
					break;
				}
				else if (hoursAfterMeal < 0) 
				{
					//console.error("Found pre-meal BG:",glucose_data[i].glucose, bgTime, Math.round(hoursAfterMeal*100)/100);
					foundPreMealBG = true;
				}
				//console.error(glucose_data[i].glucose, bgTime, Math.round(hoursAfterMeal*100)/100, bucketed_data[bucketed_data.length-1].display_time);
				// only consider last ~45m of data in CI mode
				// this allows us to calculate deviations for the last ~30m
				
				//trace("ciTime", ciTime);
				
				if (!isNaN(ciTime)) 
				{
					var hoursAgo:Number = (ciTime - bgTime) / (60 * 60 * 1000);
					if (hoursAgo > 1 || hoursAgo < 0) 
					{
						continue;
					}
				}
				
				if (!isNaN(bucketed_data[bucketed_data.length-1].date)) 
				{
					lastbgTime = bucketed_data[bucketed_data.length-1].date;
				} 
				else if ((lastbgi >= 0) && !isNaN(glucose_data[lastbgi].timestamp)) 
				{
					lastbgTime = glucose_data[lastbgi].timestamp;
				} 
				else 
				{ 
					trace("Could not determine last BG time"); 
				}
				
				//trace("I'm IN");
				
				var elapsed_minutes:Number = (bgTime - lastbgTime)/(60*1000);
				//console.error(bgTime, lastbgTime, elapsed_minutes);
				if(Math.abs(elapsed_minutes) > 8) 
				{
					// interpolate missing data points
					var lastbg:Number = glucose_data[lastbgi].calculatedValue;
					
					// cap interpolation at a maximum of 4h
					elapsed_minutes = Math.min(240,Math.abs(elapsed_minutes));
					//console.error(elapsed_minutes);
					
					while(elapsed_minutes > 5) 
					{
						var previousbgTime:Number = lastbgTime - (5 * 60 * 1000);
						j++;
						bucketed_data[j] = [];
						bucketed_data[j].date = previousbgTime;
						var gapDelta:Number = glucose_data[i].calculatedValue - lastbg;
						//console.error(gapDelta, lastbg, elapsed_minutes);
						var previousbg:Number = lastbg + (5/elapsed_minutes * gapDelta);
						bucketed_data[j].glucose = Math.round(previousbg);
						//console.error("Interpolated", bucketed_data[j]);
						
						elapsed_minutes = elapsed_minutes - 5;
						lastbg = previousbg;
						lastbgTime = previousbgTime;
					}
					
				} 
				else if(Math.abs(elapsed_minutes) > 2) 
				{
					j++;
					bucketed_data[j] = { glucose: glucose_data[i].calculatedValue, timestamp: bgTime, date: bgTime };
				} 
				else 
				{
					bucketed_data[j].glucose = (bucketed_data[j].glucose + glucose_data[i].calculatedValue) / 2;
				}
				
				lastbgi = i;
				//console.error(bucketed_data[j].date)
			}
			var currentDeviation:Number;
			var slopeFromMaxDeviation:Number = 0;
			var slopeFromMinDeviation:Number = 999;
			var maxDeviation:Number = 0;
			var minDeviation:Number = 999;
			var allDeviations:Array = [];
			//console.error(bucketed_data);
			
			for (i = 0; i < bucketed_data.length-3; ++i) 
			{
				bgTime = bucketed_data[i].date;
				
				var sens:Number = Number(ProfileManager.getProfileByTime(bgTime).insulinSensitivityFactors);
				
				//console.error(bgTime , bucketed_data[i].glucose, bucketed_data[i].date);
				var bg:Number;
				var avgDelta:Number;
				var delta:Number;
				if (bucketed_data[i] != null && bucketed_data[i].glucose != null && !isNaN(bucketed_data[i].glucose)) 
				{
					bg = bucketed_data[i].glucose;
					if ( bg < 39 || bucketed_data[i+3].glucose < 39) 
					{
						//trace("!");
						continue;
					}
					avgDelta = (bg - bucketed_data[i+3].glucose)/3;
					delta = (bg - bucketed_data[i+1].glucose);
				} 
				else 
				{ 
					trace("Could not find glucose data"); 
				}
				
				avgDelta = Math.round(avgDelta * 100) / 100;
				iob_inputs.clock=bgTime;
				//iob_inputs.profile.current_basal = basal.basalLookup(basalprofile, bgTime);
				//console.log(JSON.stringify(iob_inputs.profile));
				//console.error("Before: ", new Date().getTime());
				var iob:Object = get_iob(iob_inputs, true)[0];
				//console.error("After: ", new Date().getTime());
				//console.error(JSON.stringify(iob));
				
				var bgi:Number = Math.round(( -iob.activity * sens * 5 )*100)/100;
				//bgi = bgi.toFixed(2);
				//console.error(delta);
				
				//trace("delta", delta);
				//trace("bgi", bgi);
				
				var deviation:Number = delta - bgi;
				deviation = Math.round(deviation * 100) / 100;
				//deviation = deviation.toFixed(2);
				//if (deviation < 0 && deviation > -2) { console.error("BG: "+bg+", avgDelta: "+avgDelta+", BGI: "+bgi+", deviation: "+deviation); }
				// calculate the deviation right now, for use in min_5m
				if (i == 0) 
				{ 
					currentDeviation = Math.round((avgDelta-bgi)*1000)/1000;
					if (ciTime > bgTime) 
					{
						//console.error("currentDeviation:",currentDeviation,avgDelta,bgi);
						allDeviations.push(Math.round(currentDeviation));
					}
				} 
				else if (ciTime > bgTime) 
				{
					var avgDeviation:Number = Math.round((avgDelta-bgi)*1000)/1000;
					var deviationSlope:Number = (avgDeviation-currentDeviation)/(bgTime-ciTime)*1000*60*5;
					//console.error(avgDeviation,currentDeviation,bgTime,ciTime)
					if (avgDeviation > maxDeviation) 
					{
						slopeFromMaxDeviation = Math.min(0, deviationSlope);
						maxDeviation = avgDeviation;
					}
					if (avgDeviation < minDeviation) 
					{
						slopeFromMinDeviation = Math.max(0, deviationSlope);
						minDeviation = avgDeviation;
					}
					
					//console.error("Deviations:",avgDeviation, avgDelta,bgi,bgTime);
					allDeviations.push(Math.round(avgDeviation));
					//console.error(allDeviations);
				}
				
				// if bgTime is more recent than mealTime
				if(bgTime > mealTime) {
					// figure out how many carbs that represents
					// if currentDeviation is > 2 * min_5m_carbimpact, assume currentDeviation/2 worth of carbs were absorbed
					// but always assume at least profile.min_5m_carbimpact (3mg/dL/5m by default) absorption
					var ci:Number = Math.max(deviation, currentDeviation/2, 3);
					var absorbed:Number = ci * Number(profile.insulinToCarbRatios) / sens;
					// and add that to the running total carbsAbsorbed
					//console.error("carbsAbsorbed:",carbsAbsorbed,"absorbed:",absorbed,"bgTime:",bgTime,"BG:",bucketed_data[i].glucose)
					carbsAbsorbed += absorbed;
				}
			}
			
			var output:Object = {
				carbsAbsorbed: carbsAbsorbed,
				currentDeviation: currentDeviation,
				maxDeviation: maxDeviation,
				minDeviation: minDeviation,
				slopeFromMaxDeviation: slopeFromMaxDeviation,
				slopeFromMinDeviation: slopeFromMinDeviation,
				allDeviations: allDeviations
			}
				
			return output;
		}
		
		private static function get_iob(inputs:Object, currentIOBOnly:Boolean):Array
		{
			var treatmentsWithZeroTemp:Array = [];
			
			var opts:Object = {
				treatments: treatmentsList,
				profile: inputs.profile
			};
			
			var optsWithZeroTemp:Object = {
				treatments: treatmentsWithZeroTemp,
				profile: inputs.profile
			};
			
			var iobArray:Array = [];
			
			var clock:Number = inputs.clock;
			var lastBolusTime:Number = 0;
			var lastTemp:Object = {};
			lastTemp.date = 0;
			
			var OpenAPSTreatmentsList:Array = inputs.history;
			var numberOfTreatmets:int = OpenAPSTreatmentsList.length;
			for (var i:int = 0; i < numberOfTreatmets; i++) 
			{
				var treatment:Treatment = OpenAPSTreatmentsList[i];
				
				if (treatment.insulinAmount > 0) 
				{
					lastBolusTime = treatment.timestamp;
					
					break;
					//lastBolusTime = Math.max(lastBolusTime,treatment.timestamp);
				}
			}
			
			var iStop:Number;
			if (currentIOBOnly) 
			{
				// for COB calculation, we only need the zeroth element of iobArray
				iStop=1
			} else 
			{
				// predict IOB out to 4h, regardless of DIA
				iStop=4*60;
			}
			for (i=0; i<iStop; i+=5)
			{
				var t:Number = clock + i*60000;
				//console.error(t);
				var iob:IOBCalcTotals = getTotalIOBOpenAPS(t, "bilinear");
				//var iobWithZeroTemp:IOBCalcTotals = sum(optsWithZeroTemp, t);
				//console.error(opts.treatments[opts.treatments.length-1], optsWithZeroTemp.treatments[optsWithZeroTemp.treatments.length-1])
				iobArray.push(iob);
				//console.error(iob.iob, iobWithZeroTemp.iob);
				//console.error(iobArray.length-1, iobArray[iobArray.length-1]);
				//iobArray[iobArray.length-1].iobWithZeroTemp = iobWithZeroTemp;
			}
			//console.error(lastBolusTime);
			iobArray[0].lastBolusTime = lastBolusTime;
			iobArray[0].lastTemp = lastTemp;
			return iobArray;
		}
		
		public static function getLastCarbTreatment():Treatment
		{
			for(var i:int = treatmentsList.length - 1 ; i >= 0; i--)
			{
				var treatment:Treatment = treatmentsList[i];
				if (treatment.carbs > 0)
					return treatment;
			}
			
			return null;
		}
		
		public static function setPumpCOB(value:Number):void
		{
			if (isNaN(value))
				value = 0;
			
			pumpCOB = value;
		}
		
		public static function deleteTreatment(treatment:Treatment, updateNightscout:Boolean = true, nullifyTreatment:Boolean = true, deleteFromDatabase:Boolean = true):void
		{
			Trace.myTrace("TreatmentsManager.as", "deleteTreatment called!");
			
			if (treatmentsMap[treatment.ID] != null) //treatment exists
			{
				//Delete from Spike
				for(var i:int = treatmentsList.length - 1 ; i >= 0; i--)
				{
					var spikeTreatment:Treatment = treatmentsList[i] as Treatment;
					if (treatment.ID == spikeTreatment.ID)
					{
						Trace.myTrace("TreatmentsManager.as", "Treatment deleted. Type: " + spikeTreatment.type);
						
						treatmentsList.removeAt(i);
						
						//Notify listeners
						_instance.dispatchEvent(new TreatmentsEvent(TreatmentsEvent.TREATMENT_DELETED, false, false, spikeTreatment));
						
						//Delete from Nightscout
						if (updateNightscout && (NightscoutService.serviceActive || NightscoutService.followerModeEnabled))
							NightscoutService.deleteTreatment(spikeTreatment);
						
						//Delete from databse
						if ((!CGMBlueToothDevice.isFollower() || ModelLocator.INTERNAL_TESTING) && deleteFromDatabase)
							Database.deleteTreatmentSynchronous(spikeTreatment);
						
						treatmentsMap[spikeTreatment.ID] = null;
						if (nullifyTreatment) spikeTreatment = null;
						
						break;
					}
				}
			}
		}
		
		public static function updateTreatment(treatment:Treatment, updateNightscout:Boolean = true):void
		{
			Trace.myTrace("TreatmentsManager.as", "updateTreatment called! Treatment type: " + treatment.type);
			
			//Notify listeners
			_instance.dispatchEvent(new TreatmentsEvent(TreatmentsEvent.TREATMENT_UPDATED, false, false, treatment));
			
			//Update in Database
			if (!CGMBlueToothDevice.isFollower() || ModelLocator.INTERNAL_TESTING)
				Database.updateTreatmentSynchronous(treatment);
			
			//Update Nightscout
			if (updateNightscout)
				NightscoutService.uploadTreatment(treatment);
		}
		
		public static function addNightscoutTreatment(treatment:Treatment, uploadToNightscout:Boolean = false):void
		{	
			Trace.myTrace("TreatmentsManager.as", "addNightscoutTreatment called! Treatment type: " + treatment.type);
			
			//Insert in Database
			if (!CGMBlueToothDevice.isFollower() || ModelLocator.INTERNAL_TESTING)
			{
				if (treatmentsMap[treatment.ID] == null) //new treatment
					Database.insertTreatmentSynchronous(treatment);
			}
			
			if (treatmentsMap[treatment.ID] == null) //new treatment
			{
				Trace.myTrace("TreatmentsManager.as", "Adding treatment to Spike...");
				
				//Add treatment to Spike
				treatmentsList.push(treatment);
				treatmentsMap[treatment.ID] = treatment;
				
				//Notify listeners
				_instance.dispatchEvent(new TreatmentsEvent(TreatmentsEvent.TREATMENT_ADDED, false, false, treatment));
				
				//Upload to Nightscout
				if (uploadToNightscout)
					NightscoutService.uploadTreatment(treatment);
			}
		}
		
		public static function deleteInternalCalibration(timestamp:Number):void
		{
			Trace.myTrace("TreatmentsManager.as", "deleteInternalCalibration called!");
			
			for (var i:int = 0; i < treatmentsList.length; i++) 
			{
				var treatment:Treatment = treatmentsList[i] as Treatment;
				if (treatment.timestamp == timestamp && treatment.type == Treatment.TYPE_GLUCOSE_CHECK && treatment.note == ModelLocator.resourceManagerInstance.getString('treatments','sensor_calibration_note'))
				{
					Trace.myTrace("TreatmentsManager.as", "Calibration found. Deleting...");
					deleteTreatment(treatment);
					break;
				}
			}
		}
		
		public static function addTreatment(type:String):void
		{	
			Trace.myTrace("TreatmentsManager.as", "addTreatment called!");
			
			//Time
			var now:Number = new Date().valueOf();
			
			//Total Content Layout
			var totalScrollLayout:TiledRowsLayout = new TiledRowsLayout();
			totalScrollLayout.paging = Direction.HORIZONTAL;
			totalScrollLayout.tileHorizontalAlign = HorizontalAlign.LEFT;
			totalScrollLayout.tileVerticalAlign = VerticalAlign.TOP;
			totalScrollLayout.horizontalAlign = HorizontalAlign.LEFT;
			totalScrollLayout.verticalAlign = VerticalAlign.TOP;
			totalScrollLayout.useSquareTiles = false;
			
			//Total Container
			totalScrollContainer = new ScrollContainer();
			totalScrollContainer.layout = totalScrollLayout;
			totalScrollContainer.snapToPages = true;
			totalScrollContainer.horizontalScrollPolicy = ScrollPolicy.OFF;
			
			//Content Scroll Container
			var contentScrollContainerLayout:VerticalLayout = new VerticalLayout();
			
			contentScrollContainer = new ScrollContainer();
			contentScrollContainer.layout = contentScrollContainerLayout;
			contentScrollContainer.scrollBarDisplayMode = ScrollBarDisplayMode.FIXED_FLOAT;
			totalScrollContainer.addChild(contentScrollContainer);
			
			//Display Container
			var displayLayout:VerticalLayout = new VerticalLayout();
			displayLayout.horizontalAlign = HorizontalAlign.LEFT;
			displayLayout.gap = 10;
			
			treatmentInserterContainer = new LayoutGroup();
			treatmentInserterContainer.layout = displayLayout;
			contentScrollContainer.addChild(treatmentInserterContainer);
			
			//Title
			var treatmentTitle:String = "";
			if (type == Treatment.TYPE_BOLUS)
				treatmentTitle = ModelLocator.resourceManagerInstance.getString('treatments','enter_units_label');
			else if (type == Treatment.TYPE_NOTE)
				treatmentTitle = ModelLocator.resourceManagerInstance.getString('treatments','enter_note_label');
			else if (type == Treatment.TYPE_GLUCOSE_CHECK)
				treatmentTitle = ModelLocator.resourceManagerInstance.getString('treatments','enter_bg_label');
			else if (type == Treatment.TYPE_CARBS_CORRECTION)
				treatmentTitle = ModelLocator.resourceManagerInstance.getString('treatments','enter_grams_label');
			else if (type == Treatment.TYPE_MEAL_BOLUS)
				treatmentTitle = ModelLocator.resourceManagerInstance.getString('treatments','enter_meal_label');
			
			treatmentInserterTitleLabel = LayoutFactory.createLabel(treatmentTitle, HorizontalAlign.CENTER, VerticalAlign.TOP, 18, true);
			treatmentInserterContainer.addChild(treatmentInserterTitleLabel);
			
			//Fields
			if (type == Treatment.TYPE_BOLUS || type == Treatment.TYPE_CORRECTION_BOLUS || type == Treatment.TYPE_MEAL_BOLUS)
			{
				//Logical
				var canAddInsulin:Boolean = true;
				
				//Insulin Amout
				insulinTextInput = LayoutFactory.createTextInput(false, false, 159, HorizontalAlign.CENTER, true);
				insulinTextInput.textEditorProperties.softKeyboardType = SoftKeyboardType.DECIMAL;
				insulinTextInput.addEventListener(FeathersEventType.ENTER, onClearFocus);
				insulinTextInput.maxChars = 5;
				if (type == Treatment.TYPE_MEAL_BOLUS)
					insulinTextInput.prompt = ModelLocator.resourceManagerInstance.getString('treatments','insulin_text_input_prompt');
				treatmentInserterContainer.addChild(insulinTextInput);
				
				insulinSpacer = new Sprite();
				insulinSpacer.height = 10;
				treatmentInserterContainer.addChild(insulinSpacer);
			}
			
			if (type == Treatment.TYPE_GLUCOSE_CHECK)
			{
				//Glucose Amout
				glucoseTextInput = LayoutFactory.createTextInput(false, false, 159, HorizontalAlign.CENTER, true);
				glucoseTextInput.addEventListener(FeathersEventType.ENTER, onClearFocus);
				glucoseTextInput.maxChars = 4;
				treatmentInserterContainer.addChild(glucoseTextInput);
				
				glucoseSpacer = new Sprite();
				glucoseSpacer.height = 10;
				treatmentInserterContainer.addChild(glucoseSpacer);
			}
			
			if (type == Treatment.TYPE_CARBS_CORRECTION || type == Treatment.TYPE_MEAL_BOLUS)
			{
				if (type == Treatment.TYPE_MEAL_BOLUS)
				{
					var extendedCarbLayout:HorizontalLayout = new HorizontalLayout();
					extendedCarbLayout.gap = 0;
					extendedCarbLayout.verticalAlign = VerticalAlign.MIDDLE;
					extendedCarbContainer = new LayoutGroup();
					extendedCarbContainer.layout = extendedCarbLayout;
					
					carbOffSet = LayoutFactory.createNumericStepper(-300, 300, 0, 5);
					carbOffSet.validate();
					
					carbOffsetSuffix = LayoutFactory.createLabel(ModelLocator.resourceManagerInstance.getString('treatments','minutes_small_label'), HorizontalAlign.RIGHT);
					carbOffsetSuffix.validate();
				}
				
				//Carbs Amout
				carbsTextInput = LayoutFactory.createTextInput(false, false, 159, HorizontalAlign.CENTER, true);
				carbsTextInput.addEventListener(FeathersEventType.ENTER, onClearFocus);
				carbsTextInput.maxChars = 4;
				if (type == Treatment.TYPE_MEAL_BOLUS)
					carbsTextInput.prompt = ModelLocator.resourceManagerInstance.getString('treatments','carbs_text_input_prompt');
				
				if (type == Treatment.TYPE_MEAL_BOLUS)
				{
					extendedCarbContainer.addChild(carbsTextInput);
					extendedCarbContainer.addChild(carbOffSet);
					extendedCarbContainer.addChild(carbOffsetSuffix);
					treatmentInserterContainer.addChild(extendedCarbContainer);
				}
				else
					treatmentInserterContainer.addChild(carbsTextInput);
				
				//Carb absorption delay
				var carbDelayLayout:HorizontalLayout = new HorizontalLayout();
				carbDelayLayout.distributeWidths = true;
				carbDelayLayout.paddingTop = carbDelayLayout.paddingBottom = 8;
				
				carbDelayContainer = new LayoutGroup();
				carbDelayContainer.layout = carbDelayLayout;
				carbDelayGroup = new ToggleGroup();
				
				fastCarb = LayoutFactory.createRadioButton(ModelLocator.resourceManagerInstance.getString('treatments','carbs_fast_label'), carbDelayGroup);
				mediumCarb = LayoutFactory.createRadioButton(ModelLocator.resourceManagerInstance.getString('treatments','carbs_medium_label'), carbDelayGroup);
				slowCarb = LayoutFactory.createRadioButton(ModelLocator.resourceManagerInstance.getString('treatments','carbs_slow_label'), carbDelayGroup);
				
				var defaultCarbType:String = ProfileManager.getDefaultTimeAbsortionCarbType();
				if (defaultCarbType == "fast")
					carbDelayGroup.selectedItem = fastCarb;
				else if (defaultCarbType == "medium")
					carbDelayGroup.selectedItem = mediumCarb;
				else if (defaultCarbType == "slow")
					carbDelayGroup.selectedItem = slowCarb;
				else
					carbDelayGroup.selectedItem = slowCarb;
				carbDelayContainer.addChild(fastCarb);
				carbDelayContainer.addChild(mediumCarb);
				carbDelayContainer.addChild(slowCarb);
				treatmentInserterContainer.addChild(carbDelayContainer);
				
				//Food manager
				foodManagerContainer = LayoutFactory.createLayoutGroup("horizontal", HorizontalAlign.CENTER);
				treatmentInserterContainer.addChild(foodManagerContainer);
				
				foodManagerButton = LayoutFactory.createButton(ModelLocator.resourceManagerInstance.getString('treatments','load_foods_button_label'));
				foodManagerButton.addEventListener(Event.TRIGGERED, onLoadFoodManager);
				foodManagerContainer.addChild(foodManagerButton);
				
				//Spacer
				carbSpacer = new Sprite();
				carbSpacer.height = 10;
				treatmentInserterContainer.addChild(carbSpacer);
			}
			
			if (type == Treatment.TYPE_NOTE)
			{
				noteSpacer = new Sprite();
				noteSpacer.height = 10;
				treatmentInserterContainer.addChild(noteSpacer);
			}
			
			//Treatment Time
			treatmentTime = new DateTimeSpinner();
			treatmentTime.locale = Constants.getUserLocale(true);
			treatmentTime.minimum = new Date(now - TimeSpan.TIME_24_HOURS);
			treatmentTime.maximum = new Date(now);
			treatmentTime.value = new Date();
			treatmentTime.height = 30;
			treatmentInserterContainer.addChild(treatmentTime);
			if (type == Treatment.TYPE_MEAL_BOLUS)
				treatmentTime.minWidth = 270;
			treatmentTime.validate();
			
			treatmentSpacer = new Sprite();
			treatmentSpacer.height = 10;
			treatmentInserterContainer.addChild(treatmentSpacer);
			
			if (type == Treatment.TYPE_BOLUS || type == Treatment.TYPE_CORRECTION_BOLUS || type == Treatment.TYPE_MEAL_BOLUS)
				insulinTextInput.width = treatmentTime.width;
			if (type == Treatment.TYPE_GLUCOSE_CHECK)
				glucoseTextInput.width = treatmentTime.width;
			if (type == Treatment.TYPE_CARBS_CORRECTION)
			{
				carbsTextInput.width = treatmentTime.width;
				carbDelayContainer.width = treatmentTime.width;
				foodManagerContainer.width = treatmentTime.width;
			}
			else if (type == Treatment.TYPE_MEAL_BOLUS)
			{
				extendedCarbContainer.width = treatmentTime.width;
				carbsTextInput.width = treatmentTime.width - carbOffSet.width - carbOffsetSuffix.width;
				carbDelayContainer.width = treatmentTime.width;
				foodManagerContainer.width = treatmentTime.width;
			}
			
			treatmentInserterTitleLabel.width = treatmentTime.width;
			
			//Other Fields constainer
			var otherFieldsLayout:VerticalLayout = new VerticalLayout();
			otherFieldsLayout.horizontalAlign = HorizontalAlign.CENTER
			otherFieldsLayout.gap = 10;
			
			otherFieldsContainer = new LayoutGroup();
			otherFieldsContainer.layout = otherFieldsLayout;
			otherFieldsContainer.width = treatmentTime.width;
			treatmentInserterContainer.addChild(otherFieldsContainer);
			
			if (type == Treatment.TYPE_BOLUS || type == Treatment.TYPE_CORRECTION_BOLUS || type == Treatment.TYPE_MEAL_BOLUS)
			{
				//Insulin Type
				var askForInsulinConfiguration:Boolean = true;
				if (ProfileManager.insulinsList != null && ProfileManager.insulinsList.length > 0)
				{
					insulinList = LayoutFactory.createPickerList();
					var insulinDataProvider:ArrayCollection = new ArrayCollection();
					var userInsulins:Array = sortInsulinsByDefault(ProfileManager.insulinsList.concat());
					var numInsulins:int = userInsulins.length
					for (var i:int = 0; i < numInsulins; i++) 
					{
						var insulin:Insulin = userInsulins[i];
						if (insulin.name.indexOf("Nightscout") == -1 && !insulin.isHidden)
						{
							insulinDataProvider.push( { label:insulin.name, id: insulin.ID } );
							askForInsulinConfiguration = false;
						}
					}
					insulinList.dataProvider = insulinDataProvider;
					insulinList.popUpContentManager = new DropDownPopUpContentManager();
					insulinList.itemRendererFactory = function():IListItemRenderer
					{
						var renderer:DefaultListItemRenderer = new DefaultListItemRenderer();
						renderer.paddingRight = renderer.paddingLeft = 15;
						return renderer;
					};
					
					if (!askForInsulinConfiguration)
						otherFieldsContainer.addChild(insulinList);
				}
				
				if (askForInsulinConfiguration)
				{
					createInsulinButton = LayoutFactory.createButton(ModelLocator.resourceManagerInstance.getString('treatments','configure_insulins_button_label'));
					createInsulinButton.addEventListener(Event.TRIGGERED, onConfigureInsulins);
					otherFieldsContainer.addChild(createInsulinButton);
					canAddInsulin = false;
				}
			}
			
			notes = LayoutFactory.createTextInput(false, false, treatmentTime.width, HorizontalAlign.CENTER, false, false, false, true, true);
			notes.addEventListener(FeathersEventType.ENTER, onClearFocus);
			notes.prompt = ModelLocator.resourceManagerInstance.getString('treatments','treatment_name_note');
			notes.maxChars = 50;
			otherFieldsContainer.addChild(notes);
			
			//Action Buttons
			var actionFunction:Function;
			if (type == Treatment.TYPE_BOLUS)
				actionFunction = onInsulinEntered;
			else if (type == Treatment.TYPE_NOTE)
				actionFunction = onNoteEntered;
			else if (type == Treatment.TYPE_GLUCOSE_CHECK)
				actionFunction = onBGCheckEntered;
			else if (type == Treatment.TYPE_CARBS_CORRECTION)
				actionFunction = onCarbsEntered;
			else if (type == Treatment.TYPE_MEAL_BOLUS)
				actionFunction = onMealEntered;
			
			var actionLayout:HorizontalLayout = new HorizontalLayout();
			actionLayout.gap = 5;
			
			actionContainer = new LayoutGroup();
			actionContainer.layout = actionLayout;
			otherFieldsContainer.addChild(actionContainer);
			
			cancelButton = LayoutFactory.createButton(ModelLocator.resourceManagerInstance.getString('globaltranslations','cancel_button_label').toUpperCase());
			cancelButton.addEventListener(Event.TRIGGERED, closeCallout);
			actionContainer.addChild(cancelButton);
			
			if (((type == Treatment.TYPE_BOLUS || type == Treatment.TYPE_MEAL_BOLUS) && canAddInsulin) || type == Treatment.TYPE_NOTE || type == Treatment.TYPE_GLUCOSE_CHECK || type == Treatment.TYPE_CARBS_CORRECTION)
			{
				addButton = LayoutFactory.createButton(ModelLocator.resourceManagerInstance.getString('globaltranslations','add_button_label').toUpperCase());
				addButton.addEventListener(Event.TRIGGERED, actionFunction);
				actionContainer.addChild(addButton);
			}
			
			actionContainer.validate();
			
			//Callout
			calloutPositionHelper = new Sprite();
			var yPos:Number = 0;
			if (!isNaN(Constants.headerHeight))
				yPos = Constants.headerHeight - 10;
			else
			{
				if (Constants.deviceModel != DeviceInfo.IPHONE_X_Xs_XsMax_Xr)
					yPos = 68;
				else
					yPos = Constants.isPortrait ? 98 : 68;
			}
			calloutPositionHelper.y = yPos;
			calloutPositionHelper.x = Constants.stageWidth / 2;
			Starling.current.stage.addChild(calloutPositionHelper);
			
			treatmentInserterContainer.validate();
			var contentOriginalHeight:Number = treatmentInserterContainer.height + 60;
			var suggestedCalloutHeight:Number = Constants.stageHeight - yPos - 10;
			var finalCalloutHeight:Number = contentOriginalHeight > suggestedCalloutHeight ?  suggestedCalloutHeight : contentOriginalHeight;
			
			treatmentCallout = Callout.show(totalScrollContainer, calloutPositionHelper);
			treatmentCallout.disposeContent = true;
			treatmentCallout.paddingBottom = 15;
			if (finalCalloutHeight != contentOriginalHeight)
			{
				contentScrollContainerLayout.paddingRight = 10;
				treatmentCallout.paddingRight = 10;
			}
			treatmentCallout.closeOnTouchBeganOutside = false;
			treatmentCallout.closeOnTouchEndedOutside = false;
			treatmentCallout.height = finalCalloutHeight;
			treatmentCallout.paddingBottom = 0;
			treatmentCallout.addEventListener(Event.CLOSE, onTreatmentsCalloutClosed);
			treatmentCallout.validate();
			
			contentScrollContainer.height = finalCalloutHeight - 50;
			contentScrollContainer.maxHeight = finalCalloutHeight - 50;
			contentScrollContainer.validate();
			totalScrollContainer.height = finalCalloutHeight - 50;
			totalScrollContainer.maxHeight = finalCalloutHeight - 50;
			totalScrollContainer.validate();
			
			var treatmentCallOutWidth:Number = treatmentCallout.width;
			var treatmentCallOutHeight:Number = treatmentCallout.height;
			var treatmentCallOutPaddingRight:Number = treatmentCallout.paddingRight;
			var contentScrollContainerWidth:Number = contentScrollContainer.width;
			var contentScrollContainerHeight:Number = contentScrollContainer.height;
			var totalScrollContainerWidth:Number = totalScrollContainer.width;
			var totalScrollContainerHeight:Number = totalScrollContainer.height;
			
			//Keyboard Focus
			if (type == Treatment.TYPE_BOLUS || type == Treatment.TYPE_CORRECTION_BOLUS || type == Treatment.TYPE_MEAL_BOLUS)
				insulinTextInput.setFocus();
			else if (type == Treatment.TYPE_NOTE)
				notes.setFocus();
			else if (type == Treatment.TYPE_GLUCOSE_CHECK)
				glucoseTextInput.setFocus();
			else if (type == Treatment.TYPE_CARBS_CORRECTION)
				carbsTextInput.setFocus();
			
			//Final Layout Adjustments
			if (actionContainer.width > treatmentTime.width)
			{
				if (type == Treatment.TYPE_BOLUS || type == Treatment.TYPE_CORRECTION_BOLUS || type == Treatment.TYPE_MEAL_BOLUS)
					insulinTextInput.width = actionContainer.width;
				if (type == Treatment.TYPE_GLUCOSE_CHECK)
					glucoseTextInput.width = actionContainer.width;
				if (type == Treatment.TYPE_CARBS_CORRECTION)
				{
					carbsTextInput.width = actionContainer.width;
					carbDelayContainer.width = actionContainer.width;
					foodManagerContainer.width = actionContainer.width;
				}
				else if (type == Treatment.TYPE_MEAL_BOLUS)
				{
					extendedCarbContainer.width = actionContainer.width;
					carbsTextInput.width = actionContainer.width - carbOffSet.width - carbOffsetSuffix.width;
					carbDelayContainer.width = actionContainer.width;
					foodManagerContainer.width = actionContainer.width;
				}
				
				notes.width = actionContainer.width;
				treatmentInserterTitleLabel.width = actionContainer.width;
				treatmentInserterContainer.validate();
				treatmentTime.paddingLeft += (actionContainer.width - treatmentTime.width) / 2;
				treatmentInserterContainer.validate();
			}
			
			function closeCallout(e:Event):void
			{
				if (cancelButton != null) cancelButton.removeEventListener(Event.TRIGGERED, closeCallout);
				
				if (treatmentCallout != null) treatmentCallout.close();
			}
			
			function onInsulinEntered (e:Event):void
			{
				if (addButton != null) addButton.removeEventListener(Event.TRIGGERED, onInsulinEntered);
				
				if (insulinTextInput == null || insulinTextInput.text == null || !SpikeANE.appIsInForeground())
					return;
				
				insulinTextInput.text = insulinTextInput.text.replace(" ", "");
				var insulinValue:Number = Number((insulinTextInput.text as String).replace(",","."));
				if (isNaN(insulinValue) || insulinTextInput.text == "") 
				{
					AlertManager.showSimpleAlert
					(
						ModelLocator.resourceManagerInstance.getString('globaltranslations','warning_alert_title'),
						ModelLocator.resourceManagerInstance.getString('treatments','non_numeric_insulin'),
						Number.NaN,
						onAskNewBolus
					);
					
					function onAskNewBolus():void
					{
						addTreatment(type);
					}
				}
				else
				{
					var treatment:Treatment = new Treatment
					(
						Treatment.TYPE_BOLUS,
						treatmentTime.value.valueOf(),
						insulinValue,
						insulinList.selectedItem.id,
						0,
						0,
						getEstimatedGlucose(treatmentTime.value.valueOf()),
						notes.text
					);
					
					//Add to list
					treatmentsList.push(treatment);
					treatmentsMap[treatment.ID] = treatment;
					
					Trace.myTrace("TreatmentsManager.as", "Added treatment to Spike. Type: " + treatment.type);
					
					//Notify listeners
					_instance.dispatchEvent(new TreatmentsEvent(TreatmentsEvent.TREATMENT_ADDED, false, false, treatment));
					
					//Insert in DB
					if (!CGMBlueToothDevice.isFollower() || ModelLocator.INTERNAL_TESTING)
						Database.insertTreatmentSynchronous(treatment);
					
					//Upload to Nightscout
					NightscoutService.uploadTreatment(treatment);
				}
				
				if (treatmentCallout != null) treatmentCallout.close();
			}
			
			function onCarbsEntered (e:Event):void
			{

				if (addButton != null) addButton.removeEventListener(Event.TRIGGERED, onCarbsEntered);
				
				if (carbsTextInput == null || carbsTextInput.text == null || !SpikeANE.appIsInForeground())
					return;
				
				carbsTextInput.text = carbsTextInput.text.replace(" ", "");
				var carbsValue:Number = Number((carbsTextInput.text as String).replace(",","."));
				if (isNaN(carbsValue) || carbsTextInput.text == "") 
				{
					AlertManager.showSimpleAlert
					(
						ModelLocator.resourceManagerInstance.getString('globaltranslations','warning_alert_title'),
						ModelLocator.resourceManagerInstance.getString('treatments','non_numeric_carbs'),
						Number.NaN,
						onAskNewCarbs
					);
					
					function onAskNewCarbs():void
					{
						addTreatment(type);
					}
				}
				else
				{
					//Carb absorption delay
					var selectedCarbDelayIndex:int = carbDelayGroup != null && carbDelayGroup.selectedIndex >= 0 ? carbDelayGroup.selectedIndex : -1;
					var carbDelayMinutes:Number = 20;
					if (selectedCarbDelayIndex == 0)
						carbDelayMinutes = Number(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_CARB_FAST_ABSORTION_TIME));
					else if (selectedCarbDelayIndex == 1)
						carbDelayMinutes = Number(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_CARB_MEDIUM_ABSORTION_TIME));
					else if (selectedCarbDelayIndex == 2)
						carbDelayMinutes = Number(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_CARB_SLOW_ABSORTION_TIME));
					
					var treatment:Treatment = new Treatment
					(
						Treatment.TYPE_CARBS_CORRECTION,
						treatmentTime.value.valueOf(),
						0,
						"",
						carbsValue,
						0,
						getEstimatedGlucose(treatmentTime.value.valueOf()),
						notes.text,
						null,
						carbDelayMinutes
					);
					
					//Add to list
					treatmentsList.push(treatment);
					treatmentsMap[treatment.ID] = treatment;
					
					Trace.myTrace("TreatmentsManager.as", "Added treatment to Spike. Type: " + treatment.type);
					
					//Notify listeners
					_instance.dispatchEvent(new TreatmentsEvent(TreatmentsEvent.TREATMENT_ADDED, false, false, treatment));
					
					//Insert in DB
					if (!CGMBlueToothDevice.isFollower() || ModelLocator.INTERNAL_TESTING)
						Database.insertTreatmentSynchronous(treatment);
					
					//Upload to Nightscout
					NightscoutService.uploadTreatment(treatment);
				}
				
				if (treatmentCallout != null) treatmentCallout.close();
			}
			
			function onMealEntered (e:Event):void
			{
				
				if (addButton != null) addButton.removeEventListener(Event.TRIGGERED, onMealEntered);
				
				if (insulinTextInput == null || insulinTextInput.text == null || carbsTextInput == null || carbsTextInput.text == null || carbOffSet == null || !SpikeANE.appIsInForeground())
					return;
				
				insulinTextInput.text = insulinTextInput.text.replace(" ", "");
				carbsTextInput.text = carbsTextInput.text.replace(" ", "");
				var insulinValue:Number = Number((insulinTextInput.text as String).replace(",","."));
				var carbsValue:Number = Number((carbsTextInput.text as String).replace(",","."));
				
				if (isNaN(insulinValue) || insulinTextInput.text == "") 
				{
					AlertManager.showSimpleAlert
						(
							ModelLocator.resourceManagerInstance.getString('globaltranslations','warning_alert_title'),
							ModelLocator.resourceManagerInstance.getString('treatments','non_numeric_insulin'),
							Number.NaN,
							onAskNewBolus
						);
					
					function onAskNewBolus():void
					{
						addTreatment(type);
					}
				}
				else if (isNaN(carbsValue) || carbsTextInput.text == "") 
				{
					AlertManager.showSimpleAlert
						(
							ModelLocator.resourceManagerInstance.getString('globaltranslations','warning_alert_title'),
							ModelLocator.resourceManagerInstance.getString('treatments','non_numeric_carbs'),
							Number.NaN,
							onAskNewCarbs
						);
					
					function onAskNewCarbs():void
					{
						addTreatment(type);
					}
				}
				else
				{
					//Carb absorption delay
					var selectedCarbDelayIndex:int = carbDelayGroup != null && carbDelayGroup.selectedIndex >= 0 ? carbDelayGroup.selectedIndex : -1;
					var carbDelayMinutes:Number = 20;
					if (selectedCarbDelayIndex == 0)
						carbDelayMinutes = Number(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_CARB_FAST_ABSORTION_TIME));
					else if (selectedCarbDelayIndex == 1)
						carbDelayMinutes = Number(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_CARB_MEDIUM_ABSORTION_TIME));
					else if (selectedCarbDelayIndex == 2)
						carbDelayMinutes = Number(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_CARB_SLOW_ABSORTION_TIME));
					
					if (carbOffSet.value == 0)
					{
						var treatment:Treatment = new Treatment
							(
								Treatment.TYPE_MEAL_BOLUS,
								treatmentTime.value.valueOf(),
								insulinValue,
								insulinList.selectedItem.id,
								carbsValue,
								0,
								getEstimatedGlucose(treatmentTime.value.valueOf()),
								notes.text,
								null,
								carbDelayMinutes
							);
						
						//Add to list
						treatmentsList.push(treatment);
						treatmentsMap[treatment.ID] = treatment;
						
						Trace.myTrace("TreatmentsManager.as", "Added treatment to Spike. Type: " + treatment.type);
						
						//Notify listeners
						_instance.dispatchEvent(new TreatmentsEvent(TreatmentsEvent.TREATMENT_ADDED, false, false, treatment));
						
						//Insert in DB
						if (!CGMBlueToothDevice.isFollower() || ModelLocator.INTERNAL_TESTING)
							Database.insertTreatmentSynchronous(treatment);
						
						//Upload to Nightscout
						NightscoutService.uploadTreatment(treatment);
					}
					else
					{
						//Insulin portion
						var treatmentInsulin:Treatment = new Treatment
							(
								Treatment.TYPE_MEAL_BOLUS,
								treatmentTime.value.valueOf(),
								insulinValue,
								insulinList.selectedItem.id,
								0,
								0,
								getEstimatedGlucose(treatmentTime.value.valueOf()),
								notes.text
							);
						
						//Add to list
						treatmentsList.push(treatmentInsulin);
						treatmentsMap[treatmentInsulin.ID] = treatmentInsulin;
						
						Trace.myTrace("TreatmentsManager.as", "Added treatment to Spike. Type: " + treatmentInsulin.type);
						
						//Carb portion
						var carbTime:Number = treatmentTime.value.valueOf() + (carbOffSet.value * 60 * 1000);
						var nowTime:Number = new Date().valueOf();
						var treatmentCarbs:Treatment = new Treatment
							(
								Treatment.TYPE_MEAL_BOLUS,
								carbTime,
								0,
								insulinList.selectedItem.id,
								carbsValue,
								0,
								getEstimatedGlucose(carbTime <= nowTime ? carbTime : treatmentTime.value.valueOf()),
								notes.text,
								null,
								carbDelayMinutes
							);
						if (carbTime > nowTime) treatmentCarbs.needsAdjustment = true;
						
						//Add to list
						treatmentsList.push(treatmentCarbs);
						treatmentsMap[treatmentCarbs.ID] = treatmentCarbs;
						
						Trace.myTrace("TreatmentsManager.as", "Added treatment to Spike. Type: " + treatmentCarbs.type);
						
						//Notify listeners
						_instance.dispatchEvent(new TreatmentsEvent(TreatmentsEvent.TREATMENT_ADDED, false, false, treatmentInsulin));
						_instance.dispatchEvent(new TreatmentsEvent(TreatmentsEvent.TREATMENT_ADDED, false, false, treatmentCarbs));
						
						//Insert in DB
						if (!CGMBlueToothDevice.isFollower() || ModelLocator.INTERNAL_TESTING)
						{
							Database.insertTreatmentSynchronous(treatmentInsulin);
							Database.insertTreatmentSynchronous(treatmentCarbs);
						}
						
						//Upload to Nightscout
						NightscoutService.uploadTreatment(treatmentInsulin);
						NightscoutService.uploadTreatment(treatmentCarbs);
					}
				}
				
				if (treatmentCallout != null) treatmentCallout.close();
			}
			
			function onBGCheckEntered (e:Event):void
			{

				if (addButton != null) addButton.removeEventListener(Event.TRIGGERED, onBGCheckEntered);
				
				if (glucoseTextInput == null || glucoseTextInput.text == null || !SpikeANE.appIsInForeground())
					return;
				
				glucoseTextInput.text = glucoseTextInput.text.replace(" ", "");
				var glucoseValue:Number = Number((glucoseTextInput.text as String).replace(",","."));
				if (isNaN(glucoseValue) || glucoseTextInput.text == "") 
				{
					AlertManager.showSimpleAlert
						(
							ModelLocator.resourceManagerInstance.getString('globaltranslations','warning_alert_title'),
							ModelLocator.resourceManagerInstance.getString('treatments','non_numeric_glucose'),
							Number.NaN,
							onAskNewGlucose
						);
					
					function onAskNewGlucose():void
					{
						addTreatment(type);
					}
				}
				else
				{
					var glucoseValueToAdd:Number = glucoseValue;
					
					if (glucoseValueToAdd >= 30 && CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_DO_MGDL) != "true")
					{
						//User is on mmol/L but inserted a calibration in mg/dL. Let's do a conversion.
						glucoseValueToAdd = Math.round(glucoseValueToAdd * BgReading.MGDL_TO_MMOLL * 10) / 10;
					}
					
					if (glucoseValueToAdd < 30 && CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_DO_MGDL) == "true")
					{
						//User is on mg/dL but inserted a calibration in mmol/L. Let's do a conversion.
						glucoseValueToAdd = Math.round(glucoseValueToAdd * BgReading.MMOLL_TO_MGDL);
					}
					
					if (CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_DO_MGDL) != "true")
					{
						glucoseValueToAdd = Math.round(BgReading.mmolToMgdl(glucoseValueToAdd));
					}
					
					var treatment:Treatment = new Treatment
					(
						Treatment.TYPE_GLUCOSE_CHECK,
						treatmentTime.value.valueOf(),
						0,
						"",
						0,
						glucoseValueToAdd,
						glucoseValueToAdd,
						notes.text
					);
					
					//Add to list
					treatmentsList.push(treatment);
					treatmentsMap[treatment.ID] = treatment;
					
					Trace.myTrace("TreatmentsManager.as", "Added treatment to Spike. Type: " + treatment.type);
					
					//Notify listeners
					_instance.dispatchEvent(new TreatmentsEvent(TreatmentsEvent.TREATMENT_ADDED, false, false, treatment));
					
					//Insert in DB
					if (!CGMBlueToothDevice.isFollower() || ModelLocator.INTERNAL_TESTING)
						Database.insertTreatmentSynchronous(treatment);
					
					//Upload to Nightscout
					NightscoutService.uploadTreatment(treatment);
				}
				
				if (treatmentCallout != null) treatmentCallout.close();
			}
			
			function onNoteEntered (e:Event):void
			{
				if (addButton != null) addButton.removeEventListener(Event.TRIGGERED, onNoteEntered);
				
				if (notes == null || notes.text == null || !SpikeANE.appIsInForeground())
					return;
				
				if (notes.text == "")
				{
					AlertManager.showSimpleAlert
						(
							ModelLocator.resourceManagerInstance.getString('globaltranslations','warning_alert_title'),
							ModelLocator.resourceManagerInstance.getString('treatments','empty_note'),
							Number.NaN,
							onAskNewNote
						);
					
					function onAskNewNote():void
					{
						addTreatment(type);
					}
				}
				else
				{
					var treatment:Treatment = new Treatment
					(
						Treatment.TYPE_NOTE,
						treatmentTime.value.valueOf(),
						0,
						"",
						0,
						0,
						getEstimatedGlucose(treatmentTime.value.valueOf()),
						notes.text
					)
					
					//Add to list
					treatmentsList.push(treatment);
					treatmentsMap[treatment.ID] = treatment;
					
					Trace.myTrace("TreatmentsManager.as", "Added treatment to Spike. Type: " + treatment.type);
					
					//Notify listeners
					_instance.dispatchEvent(new TreatmentsEvent(TreatmentsEvent.TREATMENT_ADDED, false, false, treatment));
					
					//Insert in DB
					if (!CGMBlueToothDevice.isFollower() || ModelLocator.INTERNAL_TESTING)
						Database.insertTreatmentSynchronous(treatment);
					
					//Upload to Nightscout
					NightscoutService.uploadTreatment(treatment);
				}
				
				if (treatmentCallout != null) treatmentCallout.close();
			}
			
			function onConfigureInsulins(e:Event):void
			{
				if (createInsulinButton != null) createInsulinButton.removeEventListener(Event.TRIGGERED, onConfigureInsulins);
				
				AppInterface.instance.navigator.pushScreen( Screens.SETTINGS_PROFILE );
				
				var popupTween:Tween=new Tween(treatmentCallout, 0.3, Transitions.LINEAR);
				popupTween.fadeTo(0);
				popupTween.onComplete = function():void
				{
					treatmentCallout.close();
				}
				Starling.juggler.add(popupTween);
			}
			
			function onLoadFoodManager(e:Event):void
			{
				var contentWidth:Number = Constants.stageWidth - (Constants.stageWidth * 0.2);
				
				if (contentWidth < 270)
					contentWidth = 270;
				else if (contentWidth > 500)
					contentWidth = 500;
				
				var suggestedCalloutHeight:Number = Constants.stageHeight - yPos - 10;
				
				if (suggestedCalloutHeight > 730)
					suggestedCalloutHeight = 730;
				
				treatmentCallout.paddingRight = 10;
				treatmentCallout.width = contentWidth + treatmentCallout.paddingLeft + treatmentCallout.paddingRight + 10;
				treatmentCallout.height = suggestedCalloutHeight;
				
				if (foodManager == null)
				{	
					foodManager = new FoodManager(contentWidth, treatmentCallout.height - treatmentCallout.paddingTop - treatmentCallout.paddingBottom - 30, true);
					foodManager.addEventListener(Event.COMPLETE, onFoodManagerCompleted);
					totalScrollContainer.addChild(foodManager);
				}
				
				totalScrollContainer.scrollToPageIndex( 1, totalScrollContainer.verticalPageIndex );
			}
			
			function onFoodManagerCompleted(e:Event):void
			{
				if (treatmentCallout != null)
				{
					//Readjust Layout
					treatmentCallout.width = treatmentCallOutWidth;
					treatmentCallout.height = treatmentCallOutHeight;
					treatmentCallout.paddingRight = treatmentCallOutPaddingRight;
					contentScrollContainer.width = contentScrollContainerWidth;
					contentScrollContainer.height = contentScrollContainerHeight;
					totalScrollContainer.width = totalScrollContainerWidth;
					totalScrollContainer.height = totalScrollContainerHeight;
					
					var fiberPrecision:Number = Number(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_FOOD_MANAGER_FIBER_PRECISION));
					
					//Calculate all food carbs the user has added to the food manager
					var totalCarbs:Number = 0;
					var foodsList:Array = foodManager.cartList;
					var addedFoods:int = 0;
					var addedFoodNames:Array = [];
					
					for (var i:int = 0; i < foodsList.length; i++) 
					{
						var food:Food = foodsList[i].food;
						var quantity:Number = foodsList[i].quantity;
						var multiplier:Number = foodsList[i].multiplier;
						var carbs:Number = food.carbs;
						var fiber:Number = food.fiber;
						var substractFiber:Boolean = foodsList[i].substractFiber;
						var servingSize:Number = food.servingSize;
						var servingUnit:String = food.servingUnit;
						var defaultUnit:Boolean = food.defaultUnit;
						
						if (food == null || isNaN(quantity) || isNaN(multiplier) || isNaN(carbs)) 
							continue;
						
						if (multiplier != 1)
						{
							quantity = quantity * servingSize;
							servingUnit = foodsList[i].globalUnit != null && foodsList[i].globalUnit != "" ? foodsList[i].globalUnit : servingUnit;
						}
						
						if (substractFiber && !isNaN(fiber))
							carbs -= fiberPrecision == 1 ? fiber : (fiber / 2);
						
						var finalCarbs:Number = (quantity / servingSize) * carbs * multiplier;
						if (!isNaN(finalCarbs))
						{
							totalCarbs += finalCarbs;
							addedFoods += 1;
							addedFoodNames.push(foodsList[i].quantity + (multiplier != 1 || !defaultUnit ? " x " : " ") + servingUnit + " " + food.name);
						}
					}
					
					totalCarbs = Math.round(totalCarbs * 10) / 10;
					
					//Populate the carbs numeric stepper with all carbs from the food manager
					carbsTextInput.text = totalCarbs != 0 ? String(totalCarbs) : "";
					
					//Update foods label
					if (addedFoods > 0 && CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_FOOD_MANAGER_IMPORT_FOODS_AS_NOTE) == "true")
					{
						notes.text = addedFoodNames.join(", ");
					}
					
					//Scroll to the Bolus Wizard screen
					totalScrollContainer.scrollToPageIndex( 0, totalScrollContainer.verticalPageIndex );
				}
			}
			
			function onClearFocus(e:Event):void
			{
				if (insulinTextInput != null)
					insulinTextInput.clearFocus();
				
				if (carbsTextInput != null)
					carbsTextInput.clearFocus();
				
				if (glucoseTextInput != null)
					glucoseTextInput.clearFocus();
				
				if (notes != null)
					notes.clearFocus();
			}
			
			function onTreatmentsCalloutClosed(e:Event):void
			{
				//Dispose Components	
				if (foodManager != null)
				{
					foodManager.removeEventListener(Event.COMPLETE, onFoodManagerCompleted);
					foodManager.dispose();
					foodManager = null;
				}
				
				if (treatmentInserterTitleLabel != null)
				{
					treatmentInserterTitleLabel.removeFromParent();
					treatmentInserterTitleLabel.dispose();
					treatmentInserterTitleLabel = null;
				}
				
				if (insulinTextInput != null)
				{
					insulinTextInput.removeEventListener(FeathersEventType.ENTER, onClearFocus);
					insulinTextInput.removeFromParent();
					insulinTextInput.dispose();
					insulinTextInput = null;
				}
				
				if (glucoseTextInput != null)
				{
					glucoseTextInput.removeEventListener(FeathersEventType.ENTER, onClearFocus);
					glucoseTextInput.removeFromParent();
					glucoseTextInput.dispose();
					glucoseTextInput = null;
				}
				
				if (carbsTextInput != null)
				{
					carbsTextInput.removeEventListener(FeathersEventType.ENTER, onClearFocus);
					carbsTextInput.removeFromParent();
					carbsTextInput.dispose();
					carbsTextInput = null;
				}
				
				if (notes != null)
				{
					notes.removeEventListener(FeathersEventType.ENTER, onClearFocus);
					notes.removeFromParent();
					notes.dispose();
					notes = null;
				}
				
				if (cancelButton != null)
				{
					cancelButton.removeEventListener(Event.TRIGGERED, closeCallout);
					cancelButton.removeFromParent();
					cancelButton.dispose();
					cancelButton = null;
				}
				
				if (addButton != null)
				{
					addButton.removeEventListener(Event.TRIGGERED, actionFunction);
					addButton.removeFromParent();
					addButton.dispose();
					addButton = null;
				}
				
				if (createInsulinButton != null)
				{
					createInsulinButton.removeEventListener(Event.TRIGGERED, onConfigureInsulins);
					createInsulinButton.removeFromParent();
					createInsulinButton.dispose();
					createInsulinButton = null;
				}
				
				if (foodManagerButton != null)
				{
					foodManagerButton.removeEventListener(Event.TRIGGERED, onLoadFoodManager);
					foodManagerButton.removeFromParent();
					foodManagerButton.dispose();
					foodManagerButton = null;
				}
				
				if (insulinSpacer != null)
				{
					insulinSpacer.removeFromParent();
					insulinSpacer.dispose();
					insulinSpacer = null;
				}
				
				if (glucoseSpacer != null)
				{
					glucoseSpacer.removeFromParent();
					glucoseSpacer.dispose();
					glucoseSpacer = null;
				}
				
				if (carbOffSet != null)
				{
					carbOffSet.removeFromParent();
					carbOffSet.dispose();
					carbOffSet = null;
				}
				
				if (carbOffsetSuffix != null)
				{
					carbOffsetSuffix.removeFromParent();
					carbOffsetSuffix.dispose();
					carbOffsetSuffix = null;
				}
				
				if (fastCarb != null)
				{
					fastCarb.removeFromParent();
					fastCarb.dispose();
					fastCarb = null;
				}
				
				if (mediumCarb != null)
				{
					mediumCarb.removeFromParent();
					mediumCarb.dispose();
					mediumCarb = null;
				}
				
				if (slowCarb != null)
				{
					slowCarb.removeFromParent();
					slowCarb.dispose();
					slowCarb = null;
				}
				
				if (carbSpacer != null)
				{
					carbSpacer.removeFromParent();
					carbSpacer.dispose();
					carbSpacer = null;
				}
				
				if (noteSpacer != null)
				{
					noteSpacer.removeFromParent();
					noteSpacer.dispose();
					noteSpacer = null;
				}
				
				if (treatmentTime != null)
				{
					treatmentTime.removeFromParent();
					treatmentTime.dispose();
					treatmentTime = null;
				}
				
				if (treatmentSpacer != null)
				{
					treatmentSpacer.removeFromParent();
					treatmentSpacer.dispose();
					treatmentSpacer = null;
				}
				
				if (insulinList != null)
				{
					insulinList.removeFromParent();
					insulinList.dispose();
					insulinList = null;
				}
				
				if (calloutPositionHelper != null)
				{
					calloutPositionHelper.removeFromParent();
					calloutPositionHelper.dispose();
					calloutPositionHelper = null;
				}
				
				if (totalScrollContainer != null)
				{
					totalScrollContainer.removeFromParent();
					totalScrollContainer.dispose();
					totalScrollContainer = null;
				}
				
				if (contentScrollContainer != null)
				{
					contentScrollContainer.removeFromParent();
					contentScrollContainer.dispose();
					contentScrollContainer = null;
				}
				
				if (treatmentInserterContainer != null)
				{
					treatmentInserterContainer.removeFromParent();
					treatmentInserterContainer.dispose();
					treatmentInserterContainer = null;
				}
				
				if (extendedCarbContainer != null)
				{
					extendedCarbContainer.removeFromParent();
					extendedCarbContainer.dispose();
					extendedCarbContainer = null;
				}
				
				if (carbDelayContainer != null)
				{
					carbDelayContainer.removeFromParent();
					carbDelayContainer.dispose();
					carbDelayContainer = null;
				}
				
				if (foodManagerContainer != null)
				{
					foodManagerContainer.removeFromParent();
					foodManagerContainer.dispose();
					foodManagerContainer = null;
				}
				
				if (otherFieldsContainer != null)
				{
					otherFieldsContainer.removeFromParent();
					otherFieldsContainer.dispose();
					otherFieldsContainer = null;
				}
				
				if (actionContainer != null)
				{
					actionContainer.removeFromParent();
					actionContainer.dispose();
					actionContainer = null;
				}
				
				if (treatmentCallout != null)
				{
					treatmentCallout.removeEventListener(Event.CLOSE, onTreatmentsCalloutClosed);
					treatmentCallout.disposeContent = true;
					treatmentCallout.removeFromParent();
					treatmentCallout.dispose();
					treatmentCallout = null;
				}
				
				System.pauseForGCIfCollectionImminent(0);
				System.gc();
			}
		}
		
		private static function sortInsulinsByDefault(insulins:Array):Array
		{
			insulins.sortOn(["name"], Array.CASEINSENSITIVE);
			
			for (var i:int = 0; i < insulins.length; i++) 
			{
				var insulin:Insulin = insulins[i];
				if (insulin.isDefault && !insulin.isHidden)
				{
					//Remove it from the array
					insulins.removeAt(i);
					
					//Add it to the beginning
					insulins.unshift(insulin);
					
					break;
				}
			}
			
			return insulins;
		}
		
		public static function addExternalTreatment(treatment:Treatment):void
		{
			Trace.myTrace("TreatmentsManager.as", "addExternalTreatment called! Type: " + treatment.type);
			
			//Insert in DB
			if (!CGMBlueToothDevice.isFollower() || ModelLocator.INTERNAL_TESTING)
			{
				if (treatmentsMap[treatment.ID] == null) //new treatment
					Database.insertTreatmentSynchronous(treatment);
			}
			
			if (treatmentsMap[treatment.ID] == null) //new treatment
			{
				//Add to list
				treatmentsList.push(treatment);
				treatmentsMap[treatment.ID] = treatment;
				
				//Notify listeners
				_instance.dispatchEvent(new TreatmentsEvent(TreatmentsEvent.TREATMENT_ADDED, false, false, treatment));
				
				//Upload to Nightscout
				NightscoutService.uploadTreatment(treatment);
				
				Trace.myTrace("TreatmentsManager.as", "Treatment added to Spike");
			}
		}
		
		public static function addInternalCalibrationTreatment(glucoseValue:Number, timestamp:Number, treatmentID:String):void
		{
			Trace.myTrace("TreatmentsManager.as", "addInternalCalibrationTreatment called!");
			
			var treatment:Treatment = new Treatment
			(
				Treatment.TYPE_GLUCOSE_CHECK,
				timestamp,
				0,
				"",
				0,
				glucoseValue,
				glucoseValue,
				ModelLocator.resourceManagerInstance.getString('treatments','sensor_calibration_note'),
				treatmentID
			);
			
			if (treatmentsMap[treatment.ID] == null) //New treatment
			{
				//Insert in DB
				if (!CGMBlueToothDevice.isFollower() || ModelLocator.INTERNAL_TESTING)
					Database.insertTreatmentSynchronous(treatment);
				
				//Add to list
				treatmentsList.push(treatment);
				treatmentsMap[treatment.ID] = treatment;
				
				//Notify listeners
				_instance.dispatchEvent(new TreatmentsEvent(TreatmentsEvent.TREATMENT_ADDED, false, false, treatment));
				
				Trace.myTrace("TreatmentsManager.as", "Added internal calibration to Spike!");
			}
		}
		
		public static function addInternalSensorStartTreatment(timestamp:Number, treatmentID:String):void
		{
			Trace.myTrace("TreatmentsManager.as", "addInternalSensorStartTreatment called!");
			
			var treatment:Treatment = new Treatment
				(
					Treatment.TYPE_SENSOR_START,
					timestamp,
					0,
					"",
					0,
					0,
					getEstimatedGlucose(timestamp),
					"",
					treatmentID
				);
			
			if (treatmentsMap[treatment.ID] == null) //New treatment
			{
				//Insert in DB
				if (!CGMBlueToothDevice.isFollower() || ModelLocator.INTERNAL_TESTING)
					Database.insertTreatmentSynchronous(treatment);
				
				//Add to list
				treatmentsList.push(treatment);
				treatmentsMap[treatment.ID] = treatment;
				
				//Notify listeners
				_instance.dispatchEvent(new TreatmentsEvent(TreatmentsEvent.TREATMENT_ADDED, false, false, treatment));
				
				Trace.myTrace("TreatmentsManager.as", "Added sensor start to Spike!");
			}
		}
		
		public static function processNightscoutTreatments(nsTreatments:Array):void
		{
			Trace.myTrace("TreatmentsManager.as", "processNightscoutTreatments called!");
			
			var nightscoutTreatmentsMap:Dictionary = new Dictionary();
			var numNightscoutTreatments:int = nsTreatments.length;
			var firstReadingTimestamp:Number;
			var lastReadingTimestamp:Number;
			var now:Number = new Date().valueOf();
			
			if (ModelLocator.bgReadings != null && ModelLocator.bgReadings.length > 0)
			{
				firstReadingTimestamp = (ModelLocator.bgReadings[0] as BgReading).timestamp;
				lastReadingTimestamp = new Date().valueOf();
			}
			else
			{
				//There's still no readings in Spike. Abort!
				return
			}
				
			for(var i:int = nsTreatments.length - 1 ; i >= 0; i--)
			{
				//Define initial treatment properties
				var nsTreatment:Object = nsTreatments[i];
				var treatmentEventType:String = nsTreatment.eventType;
				var treatmentTimestamp:Number = DateUtil.parseW3CDTF(nsTreatment.created_at).valueOf();
				var treatmentID:String = nsTreatment._id;
				nightscoutTreatmentsMap[treatmentID] = nsTreatment;
				var treatmentType:String = "";
				var treatmentInsulinAmount:Number = 0;
				var treatmentInsulinID:String = "000000"; //Nightscout insulin
				var treatmentCarbs:Number = 0;
				var treatmentGlucose:Number = 0;
				var treatmentNote:String = "";
				var treatmentInsulinName:String = "";
				var treatmentInsulinDIA:Number = Number.NaN;
				var treatmentCarbDelayTime:Number = Number(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_DEFAULT_CARB_ABSORTION_TIME));
				
				if (treatmentTimestamp < firstReadingTimestamp)
				{
					//Treatment is outside timespan of first bg reading in spike. Let's ignore it
					continue;
				}
				
				if (nsTreatment.note == ModelLocator.resourceManagerInstance.getString('treatments','sensor_calibration_note') && treatmentEventType == "BG Check")
				{
					//Don't process sensor calibrations
					continue;
				}
				
				//Insulin
				if (nsTreatment.insulinID != null)
				{
					//It's a treatment from Spike Master
					treatmentInsulinID = String(nsTreatment.insulinID);
					
					if (ProfileManager.getInsulin(treatmentInsulinID) == null)
					{
						//Let's create this insulin in memory
						treatmentInsulinName = nsTreatment.insulinName != null ? nsTreatment.insulinName : ModelLocator.resourceManagerInstance.getString("treatments","nightscout_insulin");
						treatmentInsulinDIA = nsTreatment.dia != null ? nsTreatment.dia : ProfileManager.getInsulin("000000").dia;
						
						ProfileManager.addInsulin(treatmentInsulinName, treatmentInsulinDIA, nsTreatment.insulinType == null ? "Unknown" : String(nsTreatment.insulinType), false, treatmentInsulinID, true, true);
					}
				}
				
				//Carb Delay Time
				if (nsTreatment.carbDelayTime != null)
					treatmentCarbDelayTime = nsTreatment.carbDelayTime;
				
				if (treatmentEventType == "Correction Bolus" || treatmentEventType == "Bolus" || treatmentEventType == "Correction")
				{
					treatmentType = Treatment.TYPE_BOLUS;
					if (nsTreatment.insulin != null)
						treatmentInsulinAmount = Math.round(Number(nsTreatment.insulin) * 100) / 100;
				}
				else if (treatmentEventType == "Meal Bolus" || treatmentEventType == "Snack Bolus")
				{
					treatmentType = Treatment.TYPE_MEAL_BOLUS;
					if (nsTreatment.insulin != null)
						treatmentInsulinAmount = Math.round(Number(nsTreatment.insulin) * 100) / 100;
					if (nsTreatment.carbs != null)
						treatmentCarbs = Number(nsTreatment.carbs);
				}
				else if (treatmentEventType == "Combo Bolus")
				{
					if (nsTreatment.insulin != null && nsTreatment.carbs != null)
					{
						treatmentType = Treatment.TYPE_MEAL_BOLUS;
						treatmentInsulinAmount = Math.round(Number(nsTreatment.insulin) * 100) / 100;
						treatmentCarbs = Number(nsTreatment.carbs);
					}
					else if (nsTreatment.insulin != null && nsTreatment.carbs == null)
					{
						treatmentType = Treatment.TYPE_BOLUS;
						treatmentInsulinAmount = Math.round(Number(nsTreatment.insulin) * 100) / 100;
					}
					else if (nsTreatment.insulin == null && nsTreatment.carbs != null)
					{
						treatmentType = Treatment.TYPE_CARBS_CORRECTION;
						treatmentCarbs = Number(nsTreatment.carbs);
					}
					
					treatmentNote += (treatmentNote != "" ? "\n" : "") + "Combo Bolus";
				}
				else if (treatmentEventType == "Carb Correction" || treatmentEventType == "Carbs")
				{
					treatmentType = Treatment.TYPE_CARBS_CORRECTION;
					if (nsTreatment.carbs != null)
						treatmentCarbs = Number(nsTreatment.carbs);
				}
				else if (treatmentEventType == "Note")
					treatmentType = Treatment.TYPE_NOTE;
				else if (treatmentEventType == "Exercise")
				{
					treatmentType = Treatment.TYPE_NOTE;
					treatmentNote += (treatmentNote != "" ? "\n" : "") + "Exercise (NS)";
				}
				else if (treatmentEventType == "OpenAPS Offline")
				{
					treatmentType = Treatment.TYPE_NOTE;
					treatmentNote += (treatmentNote != "" ? "\n" : "") + "OpenAPS Offline";
				}
				else if (treatmentEventType == "Site Change")
				{
					treatmentType = Treatment.TYPE_NOTE;
					treatmentNote += (treatmentNote != "" ? "\n" : "") + "Pump Site Change";
				}
				else if (treatmentEventType == "Pump Battery Change")
				{
					treatmentType = Treatment.TYPE_NOTE;
					treatmentNote += (treatmentNote != "" ? "\n" : "") + "Pump Battery Change";
				}
				else if (treatmentEventType == "Resume Pump")
				{
					treatmentType = Treatment.TYPE_NOTE;
					treatmentNote += (treatmentNote != "" ? "\n" : "") + "Resume Pump";
				}
				else if (treatmentEventType == "Suspend Pump")
				{
					treatmentType = Treatment.TYPE_NOTE;
					treatmentNote += (treatmentNote != "" ? "\n" : "") + "Suspend Pump";
				}
				else if (treatmentEventType == "Announcement" && nsTreatment.notes != null && nsTreatment.notes != "")
				{
					treatmentType = Treatment.TYPE_NOTE;
					treatmentNote += (treatmentNote != "" ? "\n" : "") + "Announcement: " + nsTreatment.notes;
				}
				else if (treatmentEventType == "Profile Switch")
				{
					treatmentType = Treatment.TYPE_NOTE;
					treatmentNote += (treatmentNote != "" ? "\n" : "") + "Profile Switch" + (nsTreatment.profile != null ? ": " + nsTreatment.profile : "");
				}
				else if (treatmentEventType == "Sensor Start")
					treatmentType = Treatment.TYPE_SENSOR_START;
				else if (treatmentEventType == "BG Check")
				{
					treatmentType = Treatment.TYPE_GLUCOSE_CHECK;
					var glucoseValue:Number = Number(nsTreatment.glucose);
					if (glucoseValue < 25) //It's mmol
						glucoseValue = Math.round(BgReading.mmolToMgdl(glucoseValue));
					
					treatmentGlucose = glucoseValue;
				}
				else if (treatmentEventType == "Bolus Wizard" || treatmentEventType == "<none>")
				{
					//Process special treatments like Bolus Wizard or treatments without and event type.
					if ((nsTreatment.carbs == null || isNaN(nsTreatment.carbs))  && ((nsTreatment.insulin != null || !isNaN(nsTreatment.insulin)) && Number(nsTreatment.insulin) != 0))
					{
						//Bolus treatment
						treatmentType = Treatment.TYPE_BOLUS;
						treatmentInsulinAmount = Math.round(Number(nsTreatment.insulin) * 100) / 100;
					}
					else if (((nsTreatment.carbs != null || !isNaN(nsTreatment.carbs)) && Number(nsTreatment.carbs) != 0)  && (nsTreatment.insulin == null || isNaN(nsTreatment.insulin)))
					{
						//Carb treatment
						treatmentType = Treatment.TYPE_CARBS_CORRECTION;
						treatmentCarbs = Number(nsTreatment.carbs);
					}
					else if (((nsTreatment.carbs != null || !isNaN(nsTreatment.carbs)) && Number(nsTreatment.carbs) != 0)  && ((nsTreatment.insulin != null || !isNaN(nsTreatment.insulin)) && Number(nsTreatment.insulin) != 0))
					{
						//Meal treatment
						treatmentType = Treatment.TYPE_MEAL_BOLUS;
						treatmentInsulinAmount = Math.round(Number(nsTreatment.insulin) * 100) / 100;
						treatmentCarbs = Number(nsTreatment.carbs);
					}
				}
				
				if (nsTreatment.foodType != null && nsTreatment.foodType != "")
					treatmentNote += (treatmentNote != "" ? "\n" : "") + nsTreatment.foodType;
				
				if (nsTreatment.notes != null && nsTreatment.notes != "")
					treatmentNote += (treatmentNote != "" ? "\n" : "") + nsTreatment.notes;
				
				//Check if treatment is supported by Spike
				if (treatmentType != "")
				{
					//Check if treatment already exists in Spike
					if (treatmentsMap[treatmentID] == null)
					{
						//It's a new treatment. Let's create it
						var treatment:Treatment = new Treatment
						(
							treatmentType,
							treatmentTimestamp,
							treatmentInsulinAmount,
							treatmentInsulinID,
							treatmentCarbs,
							treatmentGlucose,
							treatmentEventType != "BG Check" ? getEstimatedGlucose(treatmentTimestamp) : treatmentGlucose,
							treatmentNote,
							treatmentID,
							treatmentCarbDelayTime
						);
						
						//If it's a future treatment let's mark that it needs adjustment for proper displaying on the chart
						if (treatmentTimestamp > now)
							treatment.needsAdjustment = true;
						
						//Add treatment to Spike and Databse
						addNightscoutTreatment(treatment);
						
						Trace.myTrace("TreatmentsManager.as", "Added nightscout treatment. Type: " + treatmentType);
					}
					else
					{
						//Treatment exists... Lets check if it was modified
						var wasTreatmentModified:Boolean = false;
						var spikeTreatment:Treatment = treatmentsMap[treatmentID];
						if (!isNaN(treatmentCarbs) && spikeTreatment.carbs != treatmentCarbs)
						{
							spikeTreatment.carbs = treatmentCarbs;
							wasTreatmentModified = true;
						}
						if (!isNaN(treatmentCarbDelayTime) && spikeTreatment.carbDelayTime != treatmentCarbDelayTime)
						{
							spikeTreatment.carbDelayTime = treatmentCarbDelayTime;
							wasTreatmentModified = true;
						}
						if (!isNaN(treatmentGlucose) && Math.abs(spikeTreatment.glucose - treatmentGlucose) >= 1) //Nightscout rounds values so we just check if the glucose value differnce is bigger than 1 to avoid triggering this on every treatment
						{
							spikeTreatment.glucose = treatmentGlucose;
							wasTreatmentModified = true;
						}
						if (!isNaN(treatmentInsulinAmount) && spikeTreatment.insulinAmount != treatmentInsulinAmount)
						{
							spikeTreatment.insulinAmount = treatmentInsulinAmount;
							wasTreatmentModified = true;
						}
						if (!isNaN(treatmentInsulinDIA) && spikeTreatment.dia != treatmentInsulinDIA)
						{
							spikeTreatment.dia = treatmentInsulinDIA;
							wasTreatmentModified = true;
						}
						if (treatmentInsulinID != "000000" && spikeTreatment.insulinID != treatmentInsulinID)
						{
							spikeTreatment.insulinID = treatmentInsulinID;
							wasTreatmentModified = true;
						}
						if (spikeTreatment.note != treatmentNote)
						{
							spikeTreatment.note = treatmentNote;
							wasTreatmentModified = true;
						}
						if (Math.abs(spikeTreatment.timestamp - treatmentTimestamp) > 1000) //parseW3CDTF ignores ms so we just check if the time difference is bigger than 1 sec to determine if the user changed the treatment type. This avoids triggering this on every treatment.
						{
							spikeTreatment.timestamp = treatmentTimestamp;
							spikeTreatment.glucoseEstimated = treatmentType != Treatment.TYPE_GLUCOSE_CHECK ? getEstimatedGlucose(treatmentTimestamp) : spikeTreatment.glucose;
							wasTreatmentModified = true;
						}
						
						if (wasTreatmentModified)
						{
							//Treatment was modified. Update Spike and notify listeners
							updateTreatment(spikeTreatment, false);
							_instance.dispatchEvent(new TreatmentsEvent(TreatmentsEvent.TREATMENT_EXTERNALLY_MODIFIED, false, false, spikeTreatment));
							
							Trace.myTrace("TreatmentsManager.as", "Updated nightscout treatment. Type: " + spikeTreatment.type);
						}
					}
				}
			}
			
			//Check for deleted treatments in Nightscout
			var numSpikeTreatments:int = treatmentsList.length;
			for (var j:int = 0; j <numSpikeTreatments; j++) 
			{
				var internalTreatment:Treatment = treatmentsList[j];
					
				if (internalTreatment.type == Treatment.TYPE_GLUCOSE_CHECK && internalTreatment.note == ModelLocator.resourceManagerInstance.getString('treatments','sensor_calibration_note'))
				{
					//Don't delete calibration treatments
					continue;
				}
					
				if (nightscoutTreatmentsMap[internalTreatment.ID] == null)
				{
					Trace.myTrace("TreatmentsManager.as", "User deleted treatment in Nightscout. Deleting in Spike as well. Type: " + internalTreatment.type);
					
					//Treatment is not present in Nightscout. User has deleted it
					deleteTreatment(internalTreatment, false, false, now - internalTreatment.timestamp < TimeSpan.TIME_24_HOURS);
					
					//Notify Listeners
					_instance.dispatchEvent(new TreatmentsEvent(TreatmentsEvent.TREATMENT_EXTERNALLY_DELETED, false, false, internalTreatment));
					
					//Nullify treatment
					internalTreatment = null;
				}
			}
			
			//Sort treatments
			treatmentsList.sortOn(["timestamp"], Array.NUMERIC);
		}
		
		public static function removeTreatmentFromMemory(treatment:Treatment):void
		{
			Trace.myTrace("TreatmentsManager.as", "removeTreatmentFromMemory called!");
			
			//Validation
			if (treatment == null)
				return;
			
			//Remove from list
			for (var i:int = 0; i < treatmentsList.length; i++) 
			{
				var internalTreatment:Treatment = treatmentsList[i];
				if (internalTreatment != null && internalTreatment.ID == treatment.ID)
				{
					Trace.myTrace("TreatmentsManager.as", "Removed expired treatment. Type: " + internalTreatment.type);
					treatmentsList.removeAt(i);
					break;
				}
			}
			
			//Remove from map
			treatmentsMap[treatment.ID] = null;
			
			//Dispose
			treatment = null;
		}
		
		public static function removeAllTreatmentsFromMemory():void
		{
			treatmentsList.length = 0;
			treatmentsMap = new Dictionary();
		}
		
		public static function getEstimatedGlucose(timestamp:Number):Number
		{
			var estimatedGlucose:Number = 100;
			
			if (ModelLocator.bgReadings != null && ModelLocator.bgReadings.length > 0)
			{
				for(var i:int = ModelLocator.bgReadings.length - 1 ; i >= 0; i--)
				{
					var reading:BgReading = ModelLocator.bgReadings[i];
					if (reading.timestamp <= timestamp)
					{
						estimatedGlucose = reading.calculatedValue != 0 ? reading.calculatedValue : 100;
						break;
					}
				}
			}
			
			return estimatedGlucose;
		}
		
		public static function getTotalActiveInsulin():Object
		{
			var activeTotalInsulin:Number = 0;
			var now:Number = new Date().valueOf();
			var firstTreatmentTimestamp:Number = now;
			
			var dataLength:int = treatmentsList.length;
			for (var i:int = 0; i < dataLength; i++) 
			{
				var treatment:Treatment = treatmentsList[i];
				
				if ((treatment.type == Treatment.TYPE_BOLUS || treatment.type == Treatment.TYPE_CORRECTION_BOLUS || treatment.type == Treatment.TYPE_MEAL_BOLUS) && treatment.calculateIOBNightscout(now).iobContrib > 0)
				{
					activeTotalInsulin += treatment.insulinAmount;
					if (treatment.timestamp < firstTreatmentTimestamp)
						firstTreatmentTimestamp = treatment.timestamp;
				}
			}
			
			return { timestamp: firstTreatmentTimestamp, insulin: activeTotalInsulin };
		}
		
		public static function getTotalActiveCarbs():Object
		{
			var activeTotalCarbs:Number = 0;
			var now:Number = new Date().valueOf();
			var firstTreatmentTimestamp:Number = now;
			
			var carbsAbsorptionRate:Number = ProfileManager.getCarbAbsorptionRate();
			
			// TODO: figure out the liverSensRatio that gives the most accurate purple line predictions
			var liverSensRatio:int = 8;
			var totalCOB:Number = 0;
			var lastCarbs:Treatment;
			
			var isDecaying:Number = 0;
			var lastDecayedBy:Number = 0;
			
			var currentProfile:Profile = ProfileManager.getProfileByTime(now);
			var isf:Number = Number(currentProfile.insulinSensitivityFactors);
			var ic:Number = Number(currentProfile.insulinToCarbRatios);
			
			var dataLength:int = treatmentsList.length;
			for (var i:int = 0; i < dataLength; i++) 
			{
				var treatment:Treatment = treatmentsList[i];
				
				if (treatment != null && (treatment.type == Treatment.TYPE_CARBS_CORRECTION || treatment.type == Treatment.TYPE_MEAL_BOLUS) && now >= treatment.timestamp)
				{
					var cCalc:CobCalc = treatment.calculateCOB(lastDecayedBy, now);
					if (cCalc != null)
					{
						var decaysin_hr:Number = (cCalc.decayedBy - now) / 1000 / 60 / 60;
									
						if (decaysin_hr > -10 && !isNaN(isf)) 
						{
							var actStart:Number = 0;
							if (lastDecayedBy != 0)
							{
								actStart = getTotalIOB(lastDecayedBy).activity;
							}
							
							var actEnd:Number = getTotalIOB(cCalc.decayedBy).activity;
							
							var avgActivity:Number = (actStart + actEnd) / 2;
							var delayedCarbs:Number = ( avgActivity *  liverSensRatio / isf ) * ic;
							var delayMinutes:Number = Math.round(delayedCarbs / carbsAbsorptionRate * 60);
							
							if (delayMinutes > 0) 
							{
								cCalc.decayedBy += (delayMinutes * 60 * 1000);
								decaysin_hr = (cCalc.decayedBy - now) / 1000 / 60 / 60;
							}
						}
						
						lastDecayedBy = cCalc.decayedBy;
						
						if (decaysin_hr > 0) 
						{
							var treatmentCOB:Number = Math.min(Number(treatment.carbs), decaysin_hr * carbsAbsorptionRate);
							if (isNaN(treatmentCOB)) treatmentCOB = 0;
							isDecaying = cCalc.isDecaying;
										
							if (treatmentCOB > 0)
							{
								activeTotalCarbs += treatment.carbs;
								if (treatment.timestamp < firstTreatmentTimestamp)
									firstTreatmentTimestamp = treatment.timestamp;
							}
						} 
					}
				}
			}
			
			return { timestamp: firstTreatmentTimestamp, carbs: activeTotalCarbs };
		}
		
		public static function getCarbTypeName(treatment:Treatment):String
		{
			var carbTypeName:String = ModelLocator.resourceManagerInstance.getString('treatments','carbs_unknown_label');
			
			if (treatment.type == Treatment.TYPE_CARBS_CORRECTION || treatment.type == Treatment.TYPE_MEAL_BOLUS)
			{
				if (treatment.carbDelayTime == Number(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_CARB_FAST_ABSORTION_TIME)))
					carbTypeName = ModelLocator.resourceManagerInstance.getString('treatments','carbs_fast_label');
				else if (treatment.carbDelayTime == Number(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_CARB_MEDIUM_ABSORTION_TIME)))
					carbTypeName = ModelLocator.resourceManagerInstance.getString('treatments','carbs_medium_label');
				else if (treatment.carbDelayTime == Number(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_CARB_SLOW_ABSORTION_TIME)))
					carbTypeName = ModelLocator.resourceManagerInstance.getString('treatments','carbs_slow_label');
			}
			
			return carbTypeName;
		}

		public static function get instance():TreatmentsManager
		{
			return _instance;
		}
	}
}