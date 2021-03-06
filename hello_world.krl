ruleset hello_world {
  meta {
    name "Hello World"
    author "Phil Windley"
    shares hello
  }
   
  global {
    hello = function(obj) {
      msg = "Hello " + obj;
      msg
    }
  }
   
  rule hello_world {
    select when echo hello
    send_directive("say", {"something": "Hello World"})
  }

  rule hello_monkey {
    select when echo monkey

    pre {
      name = event:attrs{"name"}.klog("our passed in name: ") || "Monkey"
    }

    send_directive("say", {"something": "Hello " + name})
  }
}
