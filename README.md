## StateMaschine

Minimalist state machine Kotlin library

### Installation

Just copy the file to your project.

### Usage

#### Example
```kotlin
import de.4evar.statemaschine.*

enum class TestState : State {
  STOPPED, STARTED
}

enum class TestEvent : Event {
  START, STOP
}

val sm = StateMaschine {

  transition from STOPPED to STARTED by START // you can also use "via" instead of "by"
  transition from STARTED to STOPPED by STOP

  receiving of STARTED run {
    ...
  }

  departing from STOPPED run {
    ...
  }

  arriving at STARTED run {
    println("reached STARTED")
  }
}

...

sm.start()

...

sm signal START
```

#### Details

You declare your own state and event classes by implementing State and Event interfaces. I think defining enums is the best way to go.

This implementation uses Kotlin coroutines to facility an asynchronous approach. When defining the state machine you can pass in the dispatcher, e.g. Dispatchers.Main, to use when the user defined action is executed. 

```kotlin
val sm = StateMaschine(Dispatchers.Main) {
  ...
}
```

The syntax for defining the states and transitions is as follows:

   **transition from** STATE1 **to** STATE2 (**by**|**via**) EVENT1 [**check { ... }**]

The block after **check** must return a Boolean. If the block returns true the transition is executed when the event is received.
If there is no transition defined for the event, an exception is raised. You can have more than one transition for the same event, e.g. when you have different checks for routing. They are then evaluated in the order of their definition and the first valid one is used.

The first **from** state in the first **transition** definition will become the starting state of the state machine. If you want to start from a different state you can pass that state to the `start()` method, e.g. `start(FOOBAR)`.


The syntax for describing the actions is as follows:

  **receiving of** EVENT1 [**from** STATE2] [**to** STATE2] **run** { ... }
  
  **departing from** STATE1 [**to** STATE2] [(**by**|**via**) EVENT1] **run** { ... }
  
  **arriving at** STATE1 [**from** STATE2] [(**by**|**via**) EVENT1] **run** { ... }
  
The actions are executed in the following order: 'receiving of', 'departing from', 'arriving at'. There can be multiple actions for the same conditions. They are then executed in the order they were defined.
