ruleset sensor_profile {

    meta {
        use module io.picolabs.wrangler alias wrangler
        use module temperature_store alias store
        use module wovyn_base alias wovyn
        use module io.picolabs.subscription alias subs
        shares getTemperatures, getTemperatureViolations, getCurrentTemperature, getSensorName, getSensorLocation, getThreshold, getTwilioNumber, getEci, getTx, mostRecentTemperature
    }

    global {

        mostRecentTemperature = function() {
          store:temperatures().reverse().head()
        }
        
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

        getEci = function() {
            meta:eci
        }

        getTx = function() {
            ent:subscriptionTx
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

    rule violation {
      select when wovyn threshold_violation

      event:send({"eci":getTx(),
      "domain":"section", "name":"threshold_met",
      "attrs":{
      "to": getTwilioNumber(),
      "from": "13312534023",
      "currTemp": event:attrs{"above_temp"},
      "thresholdTemp": getThreshold(),
      "name": ent:section_id
      }
      })
    }

    rule pico_ruleset_added {
        select when wrangler ruleset_installed
          where event:attr("rids") >< meta:rid
        pre {
          parent_eci = event:attr("parent_eci").klog("Parent ID: ")
          section_id = event:attr("section_id").klog("Section ID: ")
          wellKnown_eci = subs:wellKnown_Rx(){"id"}
        }

        if ent:sensor_eci.isnull() then
            wrangler:createChannel() setting(channel)



        fired {
            ent:parent_eci := parent_eci
            ent:section_id := section_id
            ent:name := event:attr("section_id")
            ent:wellKnown_Rx := event:attr("wellKnown_Rx")
            ent:sensor_eci := channel{"id"}
            ent:wellKnown_Rx := wellKnown_eci
            raise sensor event "new_subscription_request"
        }

      }

      rule channel_and_sub_to_already_exist {
        select when sensor channel_and_sub_to_already_exist
        pre {
          parent_eci = event:attr("parent_eci").klog("Parent ID: ")
          section_id = event:attr("section_id").klog("Section ID: ")
          wellKnown_eci = subs:wellKnown_Rx(){"id"}
        }


        wrangler:createChannel() setting(channel)



        fired {
            ent:parent_eci := parent_eci
            ent:section_id := section_id
            ent:name := event:attr("section_id")
            ent:wellKnown_Rx := event:attr("wellKnown_Rx")
            ent:sensor_eci := channel{"id"}
            ent:wellKnown_Rx := wellKnown_eci
            raise sensor event "new_subscription_request"
        }
    }


      rule new_sensor_channel {
          select when sensor new_subscription_request
          event:send({"eci":ent:parent_eci,
          "domain":"wrangler", "name":"subscription",
          "attrs": {
            "wellKnown_Tx":subs:wellKnown_Rx(){"id"},
            "Rx_role":"sensor_manager", "Tx_role":"sensor",
            "name":ent:name+"-sensor", "channel_type":"subscription"
          }
        })
      }

      rule auto_accept {
        select when wrangler inbound_pending_subscription_added
        pre {
          my_role = event:attr("Rx_role")
          their_role = event:attr("Tx_role")
        }

        event:send({"eci":event:attr("Tx"),
        "domain":"section", "name":"add_new_sensor_with_subscription",
        "attrs":{
        "wellKnown_Tx":event:attr("Rx"),
        "section_id":ent:section_id,
        "name":ent:name
        }
        })
        //        "wellKnown_Tx":subs:wellKnown_Rx(){"id"},


        fired {
          raise wrangler event "pending_subscription_approval"
            attributes event:attrs
          ent:subscriptionTx := event:attr("Tx")
        }
      }



      rule get_test {
        select when section get_test

        pre {
            name = event:attr("name").klog("IT GOT SENT!!!!!")
        }
      }

      rule get_sensor_report_results {
        select when section report_results

        pre {
          report_id = event:attr("report_id").klog("Report Id: ")
        }

        event:send({"eci":ent:subscriptionTx,
        "domain":"section", "name":"receive_report",
        "attrs":{
        "wellKnown_Rx":ent:wellKnown_Rx,
        "section_id":ent:section_id,
        "name":ent:name,
        "temperature": mostRecentTemperature(),
        "report_id": report_id,
        "num_sensors": event:attr("num_sensors")
        }
        })
      }
}