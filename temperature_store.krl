ruleset temperature_store {

    meta {
        provides temperatures, threshold_violations, inrange_temperatures
        shares temperatures, threshold_violations, inrange_temperatures
    }

    global {
        temperatures = function() {
            ent:regular_temperatures.klog("All Temps: ")
          }

        threshold_violations = function() {
            ent:threshold_temperatures.klog("Threshold Temps: ")
        }

        inrange_temperatures = function() {
            ent:regular_temperatures.filter(function(regTemp) {ent:threshold_temperatures.none(function(thresTemp) {thresTemp{"temp"} == regTemp{"temp"}})}).klog("Regular Temps without Thresholds: ")
        }
    }



    rule collect_temperatures {
        select when wovyn new_temperature_reading

        pre {
            temperature = event:attrs{"temperature"}
        }

        always {
            singleTemp = temperature.head(){"temperatureF"}
            ent:regular_temperatures := ent:regular_temperatures.append({
                "temp": singleTemp,
                "timestamp": time:now()
            }).klog("Collect REGULAR Temperatures: ")
        }

    }

    rule collect_threshold_violations {
        select when wovyn threshold_violation

        always {
            ent:threshold_temperatures := ent:threshold_temperatures.append({
                "temp": event:attrs{"above_temp"},
                "timestamp": time:now()
            }).klog("Collect THRESHOLD Temperatures: ")
        }
    }

    rule clear_temeratures {
        select when sensor reading_reset

        send_directive("Response", "Temperatures have been cleared successfully!")

        always {
            ent:regular_temperatures := []
            ent:threshold_temperatures := []
        }

    }
}