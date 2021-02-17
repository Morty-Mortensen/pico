ruleset sensor_profile {

    meta {
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

}