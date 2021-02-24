ruleset manage_sensors {

    meta {
        use module io.picolabs.wrangler alias wrangler
        provides showChildren, sensors, sensorECIByName, getTemperaturesOfAllChildren
        shares showChildren, sensors, sensorECIByName, getTemperaturesOfAllChildren
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

        sensorECIByName = function(sensor_id) {
            ent:sensors{sensor_id}
        }

        getTemperaturesOfAllChildren = function() {
            ent:sensors.map(function(v,k) {{"temperatures": {
                "name": k,
                "values": ctx:query(v.get("eci"), "temperature_store", "temperatures"),
            }}})
        }



        custom_rules = [
            {
                "absoluteURL": meta:rulesetURI, //"file:///Users/tyler/School/Winter-2021/CS462-DistributedSystems/lab6/manage_sensors.krl" 
                "rid": "io.picolabs.twilio_v2",
                "config": {}
            },
            {
                "absoluteURL": meta:rulesetURI, //"file:///Users/tyler/School/Winter-2021/CS462-DistributedSystems/lab6/manage_sensors.krl" 
                "rid": "temperature_store",
                "config": {}
            },
            {
                "absoluteURL": meta:rulesetURI, //"file:///Users/tyler/School/Winter-2021/CS462-DistributedSystems/lab6/manage_sensors.krl" 
                "rid": "wovyn_base",
                "config": {}
            },
            {
                "absoluteURL": meta:rulesetURI, //"file:///Users/tyler/School/Winter-2021/CS462-DistributedSystems/lab6/manage_sensors.krl" 
                "rid": "sensor_profile",
                "config": {}
            },
            {
                "absoluteURL": meta:rulesetURI, //"file:///Users/tyler/School/Winter-2021/CS462-DistributedSystems/lab6/manage_sensors.krl" 
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
          ent:sensors{section_id} := eci_section on final
        }
    }

    rule pico_ruleset_added {
        select when sensor ruleset_installed
        pre {
          section_id = event:attr("section_id").klog("ABOUT TO SEND TO NEW RULESETT WOOOOOHHOOOOOOOOOO")
        }

        ctx:event(ent:sensors{section_id}.get("eci"), "sensor", "profile_updated", {"threshold": default_threshold, "number": default_twilio_number, "name": sensorECIByName(section_id), "location": ""})


      }

    rule pico_ruleset_added_parent {
        select when sensor add_default

        pre {
          section_id = event:attr("section_id").klog("ABOUT TO SEND TO NEW RULESETT PARENT")
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
}