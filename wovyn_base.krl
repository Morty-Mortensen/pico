ruleset wovyn_base {

    meta {
        use module io.picolabs.twilio_v2 alias twilio
        with account_sid = meta:rulesetConfig{"account_sid"}
             auth_token =  meta:rulesetConfig{"auth_token"}
        
        use module temperature_store alias store
            
    }

    global {
        temp_threshold = 77.10
        toNumber = "8018746074"
        fromNumber = "13312534023"
    }

    rule process_heartbeat {
        select when wovyn heartbeat

        
        pre {
            response = event:attrs
        }




        always {
            reg_temp_test = store:temperatures().map(function(x) {(x{"temp"} + " - " + x{"timestamp"}).klog("TEMP ANY VALUE: ")})
            threshold_temp_test = store:threshold_violations().map(function(x) {(x{"temp"} + " - " + x{"timestamp"}).klog("TEMP ABOVE THRESHOLD (" + temp_threshold + "): ")})
            reg_temps_not_above_threshold = store:inrange_temperatures().map(function(x) {(x{"temp"} + " - " + x{"timestamp"}).klog("TEMP NOT ABOVE THRESHOLD (" + temp_threshold + "): ")})
            raise wovyn event "new_temperature_reading"
                attributes {"temperature": response{"genericThing"}{"data"}{"temperature"}}
            if not response{"genericThing"}.isnull() && response{"genericThing"} != ""
        }
    }

    rule find_high_temps {
        select when wovyn new_temperature_reading

        pre {
            temperature = event:attrs{"temperature"}.klog("TEMPERATURES")
            above_threshold_temps = temperature.filter(function(temp) {temp{"temperatureF"}.klog("CHECK HIGHER THRESHOLD VALUES") > temp_threshold}).klog("OUTPUT of ABOVE THRESHOLD")
            any_above = temperature.any(function(x) {x{"temperatureF"} > temp_threshold}).klog("ABOVE THRESHOLD? - ")
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

        }

        twilio:send_sms(toNumber,
        fromNumber,
        "The temperature " + event:attrs{"above_temp"} + " is above the threshold of " + temp_threshold

            
       )
    }

}