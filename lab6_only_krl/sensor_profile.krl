ruleset sensor_profile {

    meta {
        use module io.picolabs.wrangler alias wrangler
        use module temperature_store alias store
        use module wovyn_base alias wovyn
        shares getTemperatures, getTemperatureViolations, getCurrentTemperature, getSensorName, getSensorLocation, getThreshold, getTwilioNumber
    }

    global {
        
        getTemperatures = function() {
            store:temperatures().reverse()
        }

        getTemperatureViolations = function() {
            store:threshold_violations().reverse()
        }

        getCurrentTemperature = function() {
            store:current_temperature()
        }

        getSensorName = function() {
            wovyn:getName()
        }

        getSensorLocation = function() {
            wovyn:getLocation()
        }

        getThreshold = function() {
            wovyn:getThreshold()
        }

        getTwilioNumber = function() {
            wovyn:getTwilioNumber()
        }
    }

    rule update {
        select when sensor profile_updated

        pre {
            threshold_temp = event:attrs{"threshold"}
            twilio_number = event:attrs{"number"}
            name = event:attrs{"name"}
            location = event:attrs{"location"}
        }

        always {
            raise wovyn event "set_values"
            attributes {"threshold": threshold_temp, "number": twilio_number, "name": name, "location": location}
        }

    }

    rule pico_ruleset_added {
        select when wrangler ruleset_installed
          where event:attr("rids") >< meta:rid
        pre {
          parent_eci = event:attr("parent_eci").klog("Section ID: ")
          section_id = event:attr("section_id").klog("Section ID: ")
        }

        ctx:event(parent_eci, "sensor", "ruleset_installed", {"section_id": section_id})

      }
}