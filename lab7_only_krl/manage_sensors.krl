ruleset manage_sensors {

    meta {
      use module manage_sensors_profile alias profile
        use module io.picolabs.wrangler alias wrangler
        use module io.picolabs.subscription alias subs
        provides showChildren, sensors, sensorECIByName, getTemperaturesOfAllChildren, sensorBySubscription, getEci
        shares showChildren, sensors, sensorECIByName, getTemperaturesOfAllChildren, sensorBySubscription, getEci
    }

    global {
        nameFromID = function(sensor_id) {
            "Sensor " + sensor_id + " Pico"
          }
        showChildren = function() {
            wrangler:children()
          }

        sensors = function() {
            ent:sensors
        }

        sensorECIByName = function(section_id) {
            ent:sensors{section_id}
        }

        getTemperaturesOfAllChildren = function() {
            ent:sensors.map(function(v,k) {{"temperatures": {
                "name": k,
                "values": ctx:query(v.get("child_eci").get("eci"), "temperature_store", "temperatures"),
            }}})
        }

        sensorBySubscription = function(){
          subs:established("Tx_role", "sensor")
        }

        getEci = function() {
          meta:eci
        }



        custom_rules = [
            {
                "absoluteURL": meta:rulesetURI, //"file:///Users/tyler/School/Winter-2021/CS462-DistributedSystems/lab7/manage_sensors.krl" 
                "rid": "io.picolabs.twilio_v2",
                "config": {}
            },
            {
                "absoluteURL": meta:rulesetURI, //"file:///Users/tyler/School/Winter-2021/CS462-DistributedSystems/lab7/manage_sensors.krl" 
                "rid": "temperature_store",
                "config": {}
            },
            {
                "absoluteURL": meta:rulesetURI, //"file:///Users/tyler/School/Winter-2021/CS462-DistributedSystems/lab7/manage_sensors.krl" 
                "rid": "wovyn_base",
                "config": {}
            },
            {
                "absoluteURL": meta:rulesetURI, //"file:///Users/tyler/School/Winter-2021/CS462-DistributedSystems/lab7/manage_sensors.krl" 
                "rid": "sensor_profile",
                "config": {}
            },
            {
                "absoluteURL": meta:rulesetURI, //"file:///Users/tyler/School/Winter-2021/CS462-DistributedSystems/lab7/manage_sensors.krl" 
                "rid": "io.picolabs.wovyn.emitter",
                "config": {}
            },
        ]

        default_threshold = 80
        default_twilio_number = "8018746074"
    }

    rule sensor_info {
        select when sensor info
        send_directive("info", {"sensor_info":sensors()})
    }


    rule new_sensor {
        select when sensor new_sensor
        pre {
            section_id = event:attr("section_id")
            exists = ent:sensors && ent:sensors >< section_id
          }
          if not exists then noop()
          fired {
            raise wrangler event "new_child_request"
              attributes { "name": nameFromID(section_id), "backgroundColor": "#ff69b4", "section_id":section_id }
          }
    }

    rule sensors {
        select when sensor get_sensors

        pre {
            section_id = event:attr("section_id")
        }

        send_directive("getting_eci", {"ECI":sensorECIByName(section_id)})
    }
    
    rule store_new_sensor {
        select when wrangler new_child_created
        foreach custom_rules setting(x,i)

        pre {
          eci_section = {"eci": event:attr("eci")}
          section_id = event:attr("section_id")
        }
        if section_id.klog("found section_id") then
        event:send(
            { "eci": eci_section.get("eci"), 
              "eid": "install-ruleset", // can be anything, used for correlation
              "domain": "wrangler", "type": "install_ruleset_request",
              "attrs": {
                "absoluteURL": x{"absoluteURL"}, //meta:rulesetURI
                "rid": x{"rid"},
                "config": x{"config"},
                "section_id": section_id,
                "parent_eci": meta:eci,
              }
            }
          )

        fired {
          ent:sensors{[section_id, "child_eci"]} := eci_section on final
        }
    }

    rule delete_new_sensor {
        select when sensor unneeded_sensor
        pre {
            sensor_id = event:attr("sensor_id")
          exists = ent:sensors >< sensor_id
          eci_to_delete = ent:sensors{[sensor_id,"eci"]}
        }
        if exists && eci_to_delete then
          send_directive("deleting_section", {"sensor_id":sensor_id})
        fired {
          raise wrangler event "child_deletion_request"
            attributes {"eci": eci_to_delete};
          clear ent:sensors{sensor_id}
        }
    }

    rule empty_sensor {
        select when sensor empty
        always {
            ent:sensors := {}
          }
    }

    rule introduce_section_to_student {
      select when section add_new_sensor_with_subscription
      pre {
        section_id = event:attr("section_id").klog("PARENT RECEIVED FROM THE CHILD OVER THE CHANNEL")
        wellKnown_Tx = event:attr("wellKnown_Tx")
      }

      ctx:event(ent:sensors{[section_id, "child_eci"]}.get("eci"), "sensor", "profile_updated", {"threshold": default_threshold, "number": default_twilio_number, "name": sensorECIByName(section_id), "location": ""})

      fired {
        ent:sensors{[section_id,"wellKnown_Tx"]} := wellKnown_Tx
      }

    }

    rule add_channel_and_sub_to_already_existing_pico {
      select when section add_channel_and_sub_to_existing_pico
      pre {
        eci = event:attr("eci").klog("Pico to connect to manage_sensors")
        section_id = event:attr("section_id").klog("Pico to connect to manage_sensors")
        parent_eci = event:attr("parent_eci").klog("Pico to connect to manage_sensors")
      }

      ctx:event(eci, "sensor", "channel_and_sub_to_already_exist", {"section_id": section_id, "parent_eci": parent_eci})

      fired {
        ent:sensors{[section_id, "child_eci"]} := {"eci": eci}
      }

    //   event:send({"eci":ent:sensors{[section_id,"wellKnown_Tx"]},
    //   "domain":"sensor", "name":"channel_and_sub_to_already_exist",
    //   "attrs":{
    //     "wellKnown_Tx":subs:wellKnown_Rx(){"id"},
    //     "Rx_role":"sensor", "Tx_role":"sensor_manager",
    //     "name":"", "channel_type":"subscription",
    //     "section_id":section_id,
    //     "parent_id": meta:eci
    //   }
    // })
    }

    rule send_to_child {
      select when section send_test

      pre {
        section_id = event:attr("section_id")
      }

      event:send({"eci":ent:sensors{[section_id,"wellKnown_Tx"]},
      "domain":"section", "name":"get_test",
      "attrs":{
        "wellKnown_Tx":subs:wellKnown_Rx(){"id"},
        "Rx_role":"sensor", "Tx_role":"sensor_manager",
        "name":"", "channel_type":"subscription",
        "section_id":section_id
      }
    })
    }

    rule sms_thresholds_from_sensors {
      select when section threshold_met

      profile:send_sms(event:attr("to"), event:attr("from"), event:attr("currTemp"), event:attr("thresholdTemp"), event:attr("name"))
    }
}