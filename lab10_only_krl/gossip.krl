ruleset gossip {


    meta {
        use module wovyn_base alias wovyn
        use module io.picolabs.subscription alias subs
        use module temperature_store alias store
        provides sensorBySubscription, getRumors, getSeenMessages, getThreshold, constructRumorMessage
        shares sensorBySubscription, getRumors, getSeenMessages, getThreshold, constructRumorMessage
    }

    global {

        default_rumor_heartbeat_period = 300
        default_seen_heartbeat_period = 20

        EXPERIENCING_THRESHOLD_VIOLATION = 1
        STILL_EXPERIENCING_THRESHOLD_VIOLATION = 0
        NO_LONGER_EXPERIENCING_THRESHOLD_VIOLATION = -1

        // {
        //     "Rx_role": "node",
        //     "Tx_role": "node",
        //     "Id": "ckmwaqxyg00de0bsvfzme26cj",
        //     "Tx": "ckmwaqxyg00df0bsvhz8ye0sb",
        //     "Rx": "ckmwaqxyn00dh0bsv69ij69id"
        //   }

        sensorBySubscription = function(){
            subs:established("Tx_role", "node")
          }

          mostRecentTemperature = function() {
            store:temperatures().reverse().head()
          }

        getHighestMessageReceived = function(message_num, messageId) {
            curr_num = ent:seen_messages{messageId}

            result = checkIfAllMissingValuesHaveBeenFound(message_num, messageId)
            result
        }
        
        checkIfAllMissingValuesHaveBeenFound = function(message_num, messageId) {
            newValue = 0;
            rumors = ent:rumor_messages{messageId}.klog("Rumors: ")
            sorted_rumors = rumors.sort(function(x,y) {
                x{"MessageID"}.split(re#:#)[1].as("Number") <=> y{"MessageID"}.split(re#:#)[1].as("Number")
            }).klog("Sort: ")
            has_all = sorted_rumors.all(function(x, i) {
                
                newValue = x{"MessageID"}.split(re#:#)[1].as("Number") != i => i-1 | newValue
                x{"MessageID"}.split(re#:#)[1].as("Number").klog("Rumor Value: ") == i.klog("Index: ")
            }).klog("Has All: ")

            has_all => sorted_rumors[sorted_rumors.length()-1]{"MessageID"}.split(re#:#)[1].klog("Has All Value: ") | newValue.klog("Regular Value: ")
        }

        getRumors = function() {
            ent:rumor_messages
        }

        getSeenMessages = function() {
            ent:seen_messages
        }

        getThreshold = function() {
          wovyn:getThreshold()
        }

        constructRumorMessage = function(messageId, sensorId, temperature, timestamp) {

          rumor = (temperature.as("Number") >= getThreshold().as("Number")) => {
            "MessageID": messageId,
            "SensorID": sensorId,
            "Temperature": temperature,
            "ThresholdViolationState": EXPERIENCING_THRESHOLD_VIOLATION,
            "Timestamp": timestamp,
          } | {
            "MessageID": messageId,
            "SensorID": sensorId,
            "Temperature": temperature,
            "Timestamp": timestamp,
          }
          rumor
        }
    }

    rule set_period {
        select when gossip new_heartbeat_period
        always {
          ent:rumor_heartbeat_period := event:attr("rumor_heartbeat_period")
          .klog("Heartbeat period: "); // in seconds
          ent:seen_heartbeat_period := event:attr("seen_heartbeat_period")
          .klog("Heartbeat period: "); // in seconds
    
        }
      }

      rule set_rumor_state {
        select when gossip new_rumor_state
        if(event:attr("pause")) then noop();
        fired {
          ent:rumor_emitter_state := "paused";
        } else {
          ent:rumor_emitter_state := "running";
        }
      }

      rule set_seen_state {
        select when gossip new_seen_state
        if(event:attr("pause")) then noop();
        fired {
          ent:seen_emitter_state := "paused";
        } else {
          ent:seen_emitter_state := "running";
        }
      }

      rule start_seen_schedule {
          select when gossip schedule_seen
      }

      rule initialize_gossip {
        select when wrangler ruleset_installed
        where event:attr("rids") >< meta:rid

        always {
            raise gossip event "start"
        }
      }

    rule setThreshold {
      select when gissip set_threshold

      pre {
        new_threshold = event:attr("new_threshold")
      }

      always {
        raise wovyn event "set_temperature_threshold"
        attributes {"threshold": new_threshold};
      }
    }

    // Gets calls after "setThreshold" finishes up
    rule updateThresholdAfterSet {
      select when gossip threshold

      always {
        // Get all rumors associated with this pico and update threshold state for temperatures that are no longer in the threshold 
        // AND make still experience violation for those still above.
        this_rumors = ent:rumor_messages.map(function(v,k) {
          v.map(function(value) {
            k == ent:messageId => value{"MessageID"}.klog("ID: ") + " - " + value{"ThresholdViolationState"}.klog("State: ") | value
          })
        })

        ent:rumor_messages := ent:rumor_messages.map(function(outerValue,k) {
          outerValue.map(function(v) {
            (not v{"ThresholdViolationState"}.isnull() && v{"ThresholdViolationState"} != "" && (v{"Temperature"}.as("Number") >= getThreshold().as("Number")) && k == ent:messageId) => {
              "MessageID": v{"MessageID"},
              "SensorID": v{"SensorID"},
              "Temperature": v{"Temperature"},
              "ThresholdViolationState": STILL_EXPERIENCING_THRESHOLD_VIOLATION,
              "Timestamp": v{"Timestamp"},
            } | 
            (not v{"ThresholdViolationState"}.isnull() && v{"ThresholdViolationState"} != "" && (v{"Temperature"}.as("Number") < getThreshold().as("Number")) && k == ent:messageId) => {
              "MessageID": v{"MessageID"},
              "SensorID": v{"SensorID"},
              "Temperature": v{"Temperature"},
              "ThresholdViolationState": NO_LONGER_EXPERIENCING_THRESHOLD_VIOLATION,
              "Timestamp": v{"Timestamp"},
            } | 
            ((v{"ThresholdViolationState"}.isnull().klog("V State: ") || v{"ThresholdViolationState"}.klog("V State 2: ") == "") && (v{"Temperature"}.as("Number").klog("V Number: ") >= getThreshold().as("Number").klog("Threshold Number: ")) && k.klog("K Value: ") == ent:messageId.klog("Message Id: ")) => {
              "MessageID": v{"MessageID"},
              "SensorID": v{"SensorID"},
              "Temperature": v{"Temperature"},
              "ThresholdViolationState": EXPERIENCING_THRESHOLD_VIOLATION,
              "Timestamp": v{"Timestamp"},
            } |
            (not v{"ThresholdViolationState"}.isnull() && v{"ThresholdViolationState"} != "") => {
              "MessageID": v{"MessageID"},
              "SensorID": v{"SensorID"},
              "Temperature": v{"Temperature"},
              "ThresholdViolationState": v{"ThresholdViolationState"},
              "Timestamp": v{"Timestamp"},
            } | {
              "MessageID": v{"MessageID"},
              "SensorID": v{"SensorID"},
              "Temperature": v{"Temperature"},
              "Timestamp": v{"Timestamp"},
            }
          })
          })
      } 
    }

    rule start_gossip {
        select when gossip start

        pre {
            rumor_period = ent:rumor_heartbeat_period
                     .defaultsTo(event:attr("rumor_heartbeat_period") || default_rumor_heartbeat_period)
                     .klog("Initilizing rumor heartbeat period: "); // in seconds

            seen_period = ent:seen_heartbeat_period
                     .defaultsTo(event:attr("seen_heartbeat_period") || default_seen_heartbeat_period)
                     .klog("Initilizing seen heartbeat period: "); // in seconds
      
          }
        //   if ( ent:rumor_heartbeat_period.isnull() && ent:seen_heartbeat_period.isnull() && schedule:list().length() == 0) then send_directive("Initializing sensor pico");
          always {
            ent:rumor_heartbeat_period := rumor_period if ent:rumor_heartbeat_period.isnull();
            ent:rumor_emitter_state := "running"if ent:rumor_emitter_state.isnull();
            ent:seen_heartbeat_period := seen_period if ent:seen_heartbeat_period.isnull();
            ent:seen_emitter_state := "running"if ent:seen_emitter_state.isnull();
      
            schedule gossip event "heartbeat_rumor" repeat << */#{rumor_period} * * * * * >>  attributes { }
            schedule gossip event "heartbeat_seen" repeat << */#{seen_period} * * * * * >>  attributes { }
          } 
    }

    // Should create a new rumor and send it to all subscriptions.

    rule new_gossip_rumor {
        select when gossip heartbeat_rumor

        pre {
            temperatureF = event:attr("threshold_temperature") => event:attr("threshold_temperature") | (random:integer(lower = 700, upper = 800)/10) // one decimal digit of precision
            messageId = (ent:messageId.isnull() || ent:messageId == "") => random:uuid() | ent:messageId;
            combinedMessageId = messageId + ":" + (ent:num_temperatures_sent.isnull() || ent:num_temperatures_sent == ""  => 0 | ent:num_temperatures_sent + 1)
            rumor_message = constructRumorMessage(combinedMessageId, subs:wellKnown_Rx(){"id"}, temperatureF, time:strftime(time:now(), "%F %T"))
        }

        if ent:rumor_emitter_state == "running" then noop()
        fired {
            ent:messageId := messageId
            raise gossip event "send_rumor"
            attributes {"rumor": rumor_message};
        }
    }

    rule send_rumor_gossip {
        select when gossip send_rumor
        foreach sensorBySubscription() setting(sensor)

        pre {

        }

        event:send({"eci":sensor{"Tx"},
        "domain":"gossip", "name":"rumor",
        "attrs":{
          "wellKnown_Tx":subs:wellKnown_Rx(){"id"},
          "Rx_role":"node", "Tx_role":"node",
          "name":"", "channel_type":"subscription",
          "rumor_message":event:attrs{"rumor"}
        }
      })

        always {
            // Update state of pico that sent rumor.
            ent:num_temperatures_sent := ent:num_temperatures_sent.isnull() || ent:num_temperatures_sent == ""  => 0 | ent:num_temperatures_sent + 1 on final
            ent:rumor_messages{event:attrs{"rumor"}{"MessageID"}.split(re#:#)[0]} := ent:rumor_messages{event:attrs{"rumor"}{"MessageID"}.split(re#:#)[0]}.isnull() || ent:rumor_messages{event:attrs{"rumor"}{"MessageID"}.split(re#:#)[0]} == "" => [event:attrs{"rumor"}] | ent:rumor_messages{event:attrs{"rumor"}{"MessageID"}.split(re#:#)[0]}.append(event:attrs{"rumor"}) on final
            ent:seen_messages{event:attrs{"rumor"}{"MessageID"}.split(re#:#)[0]} := ent:num_temperatures_sent on final
        }
    }

    rule rumor_gossip {
        select when gossip rumor

        pre {
            rumor_message = event:attrs{"rumor_message"}.klog("Rumor Message (" + meta:host + "): ")
            rumor_message_split = rumor_message{"MessageID"}.split(re#:#)
        }

        always {
            // SensorID = subscription channel ID (to know who to send to)
            ent:rumor_messages{rumor_message_split[0]} := (ent:rumor_messages{rumor_message_split[0]}.isnull() || ent:rumor_messages{rumor_message_split[0]} == "").klog("First: ") => [rumor_message] | 
            ((not ent:rumor_messages{rumor_message_split[0]}.isnull() || ent:rumor_messages{rumor_message_split[0]} != "") && ent:rumor_messages{rumor_message_split[0]}.any(function(x) {
              (x{"MessageID"} == rumor_message{"MessageID"}).klog("Test1: ") && (x{"ThresholdViolationState"} != rumor_message{"ThresholdViolationState"}).klog("Test2: ") && (not x{"ThresholdViolationState"}.isnull()).klog("Test3: ") && (x{"ThresholdViolationState"} != "").klog("Test4: ") && (not rumor_message{"ThresholdViolationState"}.isnull()).klog("Test5: ") && (rumor_message{"ThresholdViolationState"} != "").klog("Test6: ")
            })).klog("Second: ") => ent:rumor_messages{rumor_message_split[0]}.map(function(x) {
              x{"MessageID"} == rumor_message{"MessageID"} && (x{"ThresholdViolationState"} != rumor_message{"ThresholdViolationState"} && not x{"ThresholdViolationState"}.isnull() && x{"ThresholdViolationState"} != "" && not rumor_message{"ThresholdViolationState"}.isnull() && rumor_message{"ThresholdViolationState"} != "") => {
                "MessageID": rumor_message{"MessageID"},
                "SensorID": rumor_message{"SensorID"},
                "Temperature": rumor_message{"Temperature"},
                "ThresholdViolationState": rumor_message{"ThresholdViolationState"},
                "Timestamp": rumor_message{"Timestamp"},
              } | 
              rumor_message{"ThresholdViolationState"}.isnull() || rumor_message{"ThresholdViolationState"} == "" => {
                "MessageID": x{"MessageID"},
                "SensorID": x{"SensorID"},
                "Temperature": x{"Temperature"},
                "Timestamp": x{"Timestamp"},
              } | {
                "MessageID": x{"MessageID"},
                "SensorID": x{"SensorID"},
                "Temperature": x{"Temperature"},
                "ThresholdViolationState": x{"ThresholdViolationState"},
                "Timestamp": x{"Timestamp"},
              }
            }) |
            ent:rumor_messages{rumor_message_split[0]}.append(rumor_message).klog("Third: ")

            ent:seen_messages{rumor_message_split[0]} := ent:seen_messages{rumor_message_split[0]}.isnull() || ent:seen_messages{rumor_message_split[0]} == "" => rumor_message_split[1] | 
            getHighestMessageReceived(rumor_message_split[1], rumor_message_split[0])
            
        }
    }

    // Should manually update the remors that this pico has.
    rule new_gossip_seen {
        select when gossip heartbeat_seen
        where ent:seen_emitter_state == "running"
        foreach sensorBySubscription() setting(sensor)


        event:send({"eci":sensor{"Tx"}.klog("SENDING TO: "),
        "domain":"gossip", "name":"seen",
        "attrs":{
          "wellKnown_Tx":sensor{"Rx"}.klog("RX: "),
          "Rx_role":"node", "Tx_role":"node",
          "name":"", "channel_type":"subscription",
          "seen_messages":ent:seen_messages,
          "already_have_rumors": ent:rumor_messages.values().reduce(function(x, y) {
            x.append(y)
        }),
        }
      })

    }

    rule seen_gossip {
        select when gossip seen

        pre {
            from_seen_messages = event:attrs{"seen_messages"}.klog("Seen Messages: ")
            already_have_rumors = event:attrs{"already_have_rumors"}.klog("Already Have Rumors: ")
            combined_rumors = ent:rumor_messages.values()
            .reduce(function(x, y) {
                x.append(y)
            })
            rumors_to_update = (already_have_rumors.isnull() || already_have_rumors == "" || already_have_rumors == 0) => combined_rumors | combined_rumors.filter(function(rumor) {
                (already_have_rumors.any(function(x) {(x{"MessageID"} == rumor{"MessageID"} && x{"ThresholdViolationState"} != rumor{"ThresholdViolationState"})})
                || already_have_rumors.all(function(x) {x{"MessageID"} != rumor{"MessageID"}}))
            }).klog("Rumors to update: ")
        }

        if (rumors_to_update.length() > 0) then noop()
        fired {
            raise gossip event "send_needed_rumors"
            attributes {"wellknown_Tx": event:attrs{"wellKnown_Tx"}, "needed_rumors": rumors_to_update};
        }
    }

    rule send_rumors {
        select when gossip send_needed_rumors
        foreach event:attrs{"needed_rumors"} setting(x,i)

        event:send({"eci":event:attrs{"wellknown_Tx"},
        "domain":"gossip", "name":"rumor",
        "attrs":{
          "wellKnown_Tx":subs:wellKnown_Rx(){"id"},
          "Rx_role":"node", "Tx_role":"node",
          "name":"", "channel_type":"subscription",
          "rumor_message": x.klog("Rumor Message: ")
        }
      })


    }

    rule clear_all_rumors {
        select when gossip clear 

        always {
            ent:num_temperatures_sent := null
            clear ent:rumor_messages
            clear ent:seen_messages
        }
    }
    rule clear_specific_rumor {
        select when gossip clear_sepecific_rumor

        pre {
            messageId = event:attrs{"messageId"}
            index = event:attrs{"index"}
            array = ent:rumor_messages{messageId}
            updated = array.filter(function(x, i) {
                i != index
            }) 
        }

        always {
            ent:rumor_messages{messageId} := updated
        }

    }

    rule set_rumor_number {
        select when gossip set_rumor_number
        pre {
            messageId = event:attrs{"messageId"}
            newNumber = event:attrs{"number"}
        }

        always {
            ent:seen_messages{messageId} := newNumber
        }
    }

}