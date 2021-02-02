ruleset wovyn_base {

    meta {
        use module io.picolabs.twilio_v2 alias twilio
        with account_sid = meta:rulesetConfig{"account_sid"}
             auth_token =  meta:rulesetConfig{"auth_token"}
    }

    global {
        temp_threshold = 79.50
        toNumber = "8018746074"
        fromNumber = "13312534023"
    }

    rule process_heartbeat {
        select when wovyn heartbeat

        
        pre {
            response = event:attrs
        }

        always {
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
            any_above = temperature.any(function(x) {x{"temperatureF"} > temp_threshold})
        }

        always {
            raise wovyn event "threshold_violation"
                attributes {"above_temp": above_threshold_temps.head(){"temperatureF"}.klog("WHAT IS BEING SENT OVER")}
            if any_above == true
        }
    }

    rule threshold_notification {
        select when wovyn threshold_violation

        twilio:send_sms(toNumber,
        fromNumber,
        "The temperature " + event:attrs{"above_temp"} + " is above the threshold of " + temp_threshold
       )
    }

}