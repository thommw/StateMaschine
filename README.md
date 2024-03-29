## StateMaschine

Minimalist state machine library Kotlin/Swift

### Installation

Just copy the file to your project.

### Usage

#### Kotlin example
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
    ...
  }
}

sm.start()

...

sm signal START
```

#### Swift example
```swift

enum TestEvent: String, Event {
  var name: String {
    get { return self.rawValue }
  }
  
  case START, STOP, FOOBAR
}

enum TestState: String, State {
  var name: String {
    get { return self.rawValue }
  }
  
  case STOPPED, STARTED, FOOBAR
}


let sm = StateMaschine<TestState, TestEvent>()

sm =+ TestState.STOPPED >>> TestEvent.START >>> TestState.STARTED ??? nil
sm =+ TestState.STARTED >>> TestEvent.STOP >>> TestState.STOPPED ??? nil
      
sm =< TestState.STARTED !!! { _ in print("STARTED") }
sm =< TestState.STOPPED !!! { _ in print("STOPPED") }

try sm.start()
      
TestEvent.START >>> sm
TestEvent.STOP >>> sm
```

#### Details

You declare your own state and event classes by implementing State and Event interfaces. I think defining enums is the best way to go.

The Swift implementation executes the actions in a background threat. That means you have to switch to the main thread if you want to manipulate the UI inside the action.
The Kotlin implementation uses coroutines to facilitate an asynchronous approach. When defining the state machine you can pass in the dispatcher, e.g. Dispatchers.Main, to use when the user defined action is executed. 

```kotlin
val sm = StateMaschine(Dispatchers.Main) {
  ...
}
```

The syntax for defining the states and transitions is as follows:

##### Kotlin:
   **transition from** STATE1 **to** STATE2 (**by**|**via**) EVENT1 [**check { ... }**]

The block after **check** has the signature `(StateMaschine.Transition) -> Boolean`. If the block returns true the transition is executed when the event is received.
If there is no transition defined for the received event, an exception is raised. You can have more than one transition for the same event, e.g. when you have different checks for routing. They are then evaluated in the order of their definition and the first valid one is used.

##### Swift:
  let sm = StateMaschine<TestState, TestEvent>()
  sm **=+** STATE1 **>>>** EVENT **>>>** STATE2 **???** (nil | { transition in ... })
  
The block after **???** has the signature `(StateMaschine.Transition) -> Bool`. 

The first **from** state in the first **transition** definition will become the starting state of the state machine. If you want to start from a different state you can pass that state to the `start()` method, e.g. `start(FOOBAR)`.


The syntax for describing the actions is as follows in Kotlin:

  **receiving of** EVENT1 [**from** STATE2] [**to** STATE2] **run** { ... }
  
  **departing from** STATE1 [**to** STATE2] [(**by**|**via**) EVENT1] **run** { ... }
  
  **arriving at** STATE1 [**from** STATE2] [(**by**|**via**) EVENT1] **run** { ... }
  
The **run** block has the signature `(StateMaschine.Transition) -> Unit`. The actions are executed in the following order: 'receiving of', 'departing from', 'arriving at'. There can be multiple actions for the same conditions. They are then executed in the order they were defined.

The Swift syntax:

let sm = StateMaschine<TestState, TestEvent>()

##### Execute action when an event is received:
sm **=!** EVENT1 [**>>>** TO_STATE] [**<<<** FROM_STATE] **!!!** { transition in ... }

##### Execute action when a state is departed from:
sm **=>** FROM_STATE [**>>>** TO_STATE] [**>>>** EVENT1] **!!!** { transition in ... }

##### Execute action when a state is arrived at:
sm **=<** TO_STATE [**<<<** FROM_STATE] [**>>>** EVENT1] **!!!** { transition in ... }

