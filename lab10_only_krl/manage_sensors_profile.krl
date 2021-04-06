ruleset manage_sensors_profile {

    meta {
        use module io.picolabs.twilio_v2 alias twilio
        with account_sid = meta:rulesetConfig{"account_sid"}
             auth_token =  meta:rulesetConfig{"auth_token"}

        provides send_sms
    }

    global {
        send_sms = defaction(toNumber, fromNumber, currTemp, thresholdTemp, name) {
            twilio:send_sms(toNumber.klog("TO NUMBER: "),
            fromNumber.klog("FROM NUMBER: "),
            "The temperature (from the " + name + " sensor) " + currTemp + " is above the threshold of " + thresholdTemp  
           )
        }
    }
}