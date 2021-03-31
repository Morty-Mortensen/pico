ruleset wovyn_base {

    meta {
        use module io.picolabs.twilio_v2 alias twilio
        with account_sid = meta:rulesetConfig{"account_sid"}
             auth_token =  meta:rulesetConfig{"auth_token"}
        
        use module temperature_store alias store

        provides getName, getLocation, getThreshold, getTwilioNumber
        shares getName, getLocation, getThreshold, getTwilioNumber
            
    }

    global {
        default_threshold = 77.10
        toNumber = "8014947197"
        fromNumber = "13312534023"

        getName = function() {
            (ent:sensor_name == "" || ent:sensor_name.isnull()) => "No Name Found :(" | ent:sensor_name
        }

        getLocation = function() {
            (ent:sensor_location == "" || ent:sensor_location.isnull()) => "No Location Found :(" | ent:sensor_location
        }

        getThreshold = function() {
            (ent:threshold_temp == "" || ent:threshold_temp.isnull()) => default_threshold | ent:threshold_temp
        }

        getTwilioNumber = function() {
            (ent:twilio_number == "" || ent:twilio_number.isnull()) => toNumber | ent:twilio_number
        }
    }

    // To test sending heat sensor info.
    rule raise_emitter_event {
        select when wovyn send_new_sensor_reading
    
        pre {
          // Bounds should not be fixed, but are for now
          period = ent:heartbeat_period.defaultsTo(20)
                   .klog("Heartbeat period: "); // in seconds
          temperatureF = (random:integer(lower = 700, upper = 800)/10) // one decimal digit of precision
                         .klog("TemperatureF: ");
          temperatureC = math:round((temperatureF - 32)/1.8,1);
          healthPercent = random:integer(lower = 500, upper = 900)/10; // one decimal digit of precision
          transducerGUID = ent:transducerGUID.defaultsTo(random:uuid());
          emitterGUID = ent:emitterGUID.defaultsTo(random:uuid()); 
    
          genericThing = {
                        "typeId": "2.1.2",
                        "typeName": "generic.simple.temperature",
                        "healthPercent": healthPercent,
                        "heartbeatSeconds": period,
                        "data": {
                            "temperature": [
                                {
                                    "name": "enclosure temperature",
                                    "transducerGUID": transducerGUID,
                                    "units": "degrees",
                                    "temperatureF": temperatureF,
                                    "temperatureC": temperatureC
                                }
                            ]
                        }
                      };
    
          specificThing = {
                        "make": "Wovyn ESProto",
                        "model": "Temp2000",
                        "typeId": "1.1.2.2.2000",
                        "typeName": "enterprise.wovyn.esproto.temp.2000",
                        "thingGUID": emitterGUID+".1",
                        "firmwareVersion": "Wovyn-Temp2000-1.1-DEV",
                        "transducer": [
                            {
                                "name": "Maxim DS18B20 Digital Thermometer",
                                "transducerGUID": transducerGUID,
                                "transducerType": "Maxim Integrated.DS18B20",
                                "units": "degrees",
                                "temperatureC": temperatureC
                            }
                        ],
                        "battery": {
                            "maximumVoltage": 3.6,
                            "minimumVoltage": 2.7,
                            "currentVoltage": 3.4
                        }
                    };
                    
         property = {
                        "name": "Wovyn_163A54",
                        "description": "Wovyn ESProto Temp2000",
                        "location": {
                            "description": "Timbuktu",
                            "imageURL": "http://www.wovyn.com/assets/img/wovyn-logo-small.png",
                            "latitude": "16.77078",
                            "longitude": "-3.00819"
                        }
                    };
        }

        always {
          ent:transducerGUID := transducerGUID if ent:transducerGUID.isnull();
          ent:emitterGUID := emitterGUID if ent:emitterGUID.isnull();
          raise wovyn event "heartbeat" attributes {
            "emitterGUID": emitterGUID,
            "genericThing": genericThing,
            "specificThing": specificThing,
            "property": property
            }
        }
    }

    rule process_heartbeat {
        select when wovyn heartbeat

        
        pre {
            response = event:attrs
        }




        always {
            // reg_temp_test = store:temperatures().map(function(x) {(x{"temp"} + " - " + x{"timestamp"}).klog("TEMP ANY VALUE: ")})
            // threshold_temp_test = store:threshold_violations().map(function(x) {(x{"temp"} + " - " + x{"timestamp"}).klog("TEMP ABOVE THRESHOLD (" + temp_threshold + "): ")})
            // reg_temps_not_above_threshold = store:inrange_temperatures().map(function(x) {(x{"temp"} + " - " + x{"timestamp"}).klog("TEMP NOT ABOVE THRESHOLD (" + temp_threshold + "): ")})

            ent:sensor_name := response{"property"}{"name"}.klog("Sensor Name: ")
            ent:sensor_location := response{"property"}{"location"}.klog("Sensor Location: ")


            raise wovyn event "new_temperature_reading"
                attributes {"temperature": response{"genericThing"}{"data"}{"temperature"}}
            if not response{"genericThing"}.isnull() && response{"genericThing"} != ""
        }
    }

    rule set_name_location_threshold_toNumber {
        select when wovyn set_values

        pre {
            threshold_temp = event:attrs{"threshold"}.klog("New Threshold Temperature: ")
            twilio_number = event:attrs{"number"}.klog("New Twilio Phone Number: ")
            name = event:attrs{"name"}.klog("New Name of Wovyn Device: ")
            location = event:attrs{"location"}.klog("New Location of Wovyn Device: ")
        }

        fired {
            ent:threshold_temp := threshold_temp == "" || threshold_temp.isnull() => ent:threshold_temp | threshold_temp
            ent:twilio_number := twilio_number == "" || twilio_number.isnull() => ent:twilio_number | twilio_number
            ent:sensor_name := name == "" || name.isnull() => ent:sensor_name | name
            ent:sensor_location := location == "" || location.isnull() => getLocation() | location
        }
    }

    rule find_high_temps {
        select when wovyn new_temperature_reading

        pre {
            temperature = event:attrs{"temperature"}.klog("TEMPERATURES")
            above_threshold_temps = temperature.filter(function(temp) {temp{"temperatureF"}.klog("CHECK HIGHER THRESHOLD VALUES") > getThreshold().klog("THRESHOLD: ")}).klog("OUTPUT of ABOVE THRESHOLD")
            any_above = temperature.any(function(x) {x{"temperatureF"} > getThreshold().klog("THRESHOLD: ")}).klog("ABOVE THRESHOLD? - ")
        }

        always {
            raise wovyn event "threshold_violation"
                attributes {"above_temp": above_threshold_temps.head(){"temperatureF"}.klog("WHAT IS BEING SENT OVER")}
            if any_above == true && not any_above.isnull()
        }
    }

    rule threshold_notification {
        select when wovyn threshold_violation
        pre {
            temp = event:attrs{"above_temp"}.klog("The temperature to SEND WITH TWILIO!!!!!!!!!!!!!!!!")
        }


    //     twilio:send_sms(getTwilioNumber().klog("TO NUMBER: "),
    //     fromNumber.klog("FROM NUMBER: "),
    //     "The temperature " + temp + " is above the threshold of " + getThreshold()  
    //    )
    }

}