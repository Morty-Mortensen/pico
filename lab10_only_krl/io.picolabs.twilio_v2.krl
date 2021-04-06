ruleset io.picolabs.twilio_v2 {
  meta {
    configure using account_sid = ""
                    auth_token = ""
    provides message

    provides send_sms
      
      
  }

  global {
    send_sms = defaction(to, from, message) {
       base_url = <<https://#{account_sid}:#{auth_token}@api.twilio.com/2010-04-01/Accounts/#{account_sid}/>>
       http:post(base_url + "Messages.json", form = {
                "From":from,
                "To":to,
                "Body":message
            })
    }

    message = function(pageSize = "", filterTo = "", filterFrom = "") {

      payload1 = "?"
      payload3 = pageSize => "PageSize=" + pageSize + "&" | ""
      payload4 = filterTo => "To=" + filterTo + "&" | ""
      payload5 = filterFrom => "From=" + filterFrom | ""

      payload6 = (payload1 + payload3 + payload4 + payload5) == "?" => "" | payload1 + payload3 + payload4 + payload5

      finalPayload = (payload6.substr(payload6.length() - 1, payload6.length())) == "&" => payload6.substr(0, payload6.length() - 1) | payload6


      base_url = <<https://#{account_sid}:#{auth_token}@api.twilio.com/2010-04-01/Accounts/#{account_sid}/>>
      response = http:get(base_url + "Messages.json" + finalPayload)
      response
      // finalPayload
    }

  }

  // rule test_get_messages {
  //   select when test another_message
  //   response = message(event:attr("numMessages"))
  // }
}