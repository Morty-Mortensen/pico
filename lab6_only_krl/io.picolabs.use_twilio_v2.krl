ruleset io.picolabs.use_twilio_v2 {
  meta {
    use module io.picolabs.twilio_v2 alias twilio
        with account_sid = meta:rulesetConfig{"account_sid"}
             auth_token =  meta:rulesetConfig{"auth_token"}
  }

  global {
    parseResponse = function(response) {
      messages = response{"content"}.decode()
      messages
      // response
    }
  }

  rule test_send_sms {
    select when test new_message
    twilio:send_sms(event:attr("to"),
                    event:attr("from"),
                    event:attr("message")
                   )
  }

  rule test_get_messages {
    select when test get_messages

    pre {
      response = parseResponse(twilio:message(event:attr("pageSize"), event:attr("filterTo"), event:attr("filterFrom")))
    }
    
    // twilio:message(event:attr("numMessages")) setting(response)
    send_directive("response", {"response": response})
    
  
  }
}

