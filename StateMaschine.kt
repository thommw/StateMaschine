package de.a4evar.statemaschine

import kotlin.coroutines.*
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel


typealias Condition = (StateMaschine.Transition) -> Boolean

typealias Action = (StateMaschine.Transition) -> Unit

interface State
interface Event


class StateMaschine(val context: CoroutineContext = Dispatchers.Default) :
  CoroutineScope by CoroutineScope(Dispatchers.Default) {

  val DEBUG = false

  companion object {
    val STATE_MASCHINE_START = object : Event {
      override fun toString(): String {
        return "STATE_MASCHINE_START"
      }
    }
    val STATE_MASCHINE_INITIAL = object : State {
      override fun toString(): String {
        return "STATE_MASCHINE_INITIAL"
      }
    }
  }

  private val stateNodes = mutableListOf<StateNode>()

  private var rootStateNode: StateNode? = null

  private var currentStateNode: StateNode? = null

  private val eventActions = mutableListOf<EventAction>()

  private val channel = Channel<Event>(Channel.UNLIMITED)

  val currentState
    get() = currentStateNode?.state


  fun addTransition(
    fromState: State,
    toState: State,
    vararg events: Event,
    condition: Condition? = null
  ) {
    if (events.isEmpty()) throw Exception("must specify an event")

    for (event in events) {
      var fromStateNode = stateNodes.find { it.state == fromState }
      if (fromStateNode == null) {
        if (rootStateNode == null) { // first transition added
          fromStateNode = StateNode(fromState)
          stateNodes.add(fromStateNode)
          rootStateNode = fromStateNode
        } else {
          throw Exception("fromState not found")
        }
      }

//      if (fromStateNode.events[event] != null) {
//        throw Exception("transition for event $event from state $fromState exists already")
//      }

      val transitions = fromStateNode.events[event]
      if (transitions == null) {
        fromStateNode.events[event] =
          mutableListOf(Transition(fromState, toState, event, condition))
      } else {
        transitions.add(Transition(fromState, toState, event, condition))
      }

      val toStateNode = stateNodes.find { it.state == toState }
      if (toStateNode == null) {
        stateNodes.add(StateNode(toState))
      }
    }
  }


  fun onDepartureFrom(
    fromState: State,
    toState: State? = null,
    event: Event? = null,
    action: Action
  ) {
    val fromStateNode =
      stateNodes.find { it.state == fromState } ?: throw Exception("state not found: $fromState")
    fromStateNode.departureActions.add(DepartureAction(fromState, toState, event, action))
  }


  fun onArrivalAt(toState: State, fromState: State? = null, event: Event? = null, action: Action) {
    val toStateNode =
      stateNodes.find { it.state == toState } ?: throw Exception("state not found: $toState")
    toStateNode.arrivalActions.add(ArrivalAction(toState, fromState, event, action))
  }


  fun onEvent(event: Event, fromState: State? = null, toState: State? = null, action: Action) {
    eventActions.add(EventAction(event, fromState, toState, action))
  }


  fun start(startState: State? = null) {
    if (currentStateNode != null) throw Exception("state maschine already running")
    if (startState != null) {
      currentStateNode = stateNodes.find { it.state == startState }
        ?: throw Exception("state not found: $startState")
    } else {
      currentStateNode = rootStateNode ?: throw Exception("state maschine not configured")
    }

    launch {
      try {
        for (action in currentStateNode!!.arrivalActions) {
          if (action.event == STATE_MASCHINE_START) {
            if (DEBUG) println("executing arrival action for event STATE_MASCHINE_START")
            action.execute(Transition(STATE_MASCHINE_INITIAL, currentState!!, STATE_MASCHINE_START))?.join()
            break
          }
        }

        for (event in channel) {
          if (DEBUG) println("received event $event")
          val csn = currentStateNode ?: throw Exception("state maschine not started")
          val transitions = csn.events[event] ?: throw Exception("cannot find transition")
          for (transition in transitions) {
            if (transition.isValid()) {
              if (DEBUG) println("transitioning to state ${transition.toState}")
              for (action in eventActions.filter { it.event == event }) {
                action.execute(transition)?.join()
              }

              for (action in csn.departureActions) {
                action.execute(transition)?.join()
              }

              currentStateNode = stateNodes.find { it.state == transition.toState }

              for (action in currentStateNode!!.arrivalActions) {
                action.execute(transition)?.join()
              }

              break
            }
          }
        }
      } catch (e: Throwable) {
        println(e.localizedMessage)
        throw e
      }
    }

    if (DEBUG) println("state maschine started")
  }


  fun stop() {
    channel.close()
    cancel()
  }


  infix fun signal(event: Event) {
    currentStateNode ?: throw Exception("state maschine not started")
    channel.offer(event)
  }


  inner class StateNode(val state: State) {
    internal val events = mutableMapOf<Event, MutableList<Transition>>()
    internal val departureActions = mutableListOf<DepartureAction>()
    internal val arrivalActions = mutableListOf<ArrivalAction>()
    override fun toString() = state.toString()
  }


  inner class Transition(
    val fromState: State,
    val toState: State,
    val event: Event,
    val condition: Condition? = null
  ) {
    fun isValid() = condition?.invoke(this) ?: true
    override fun toString(): String {
      return "Transition $fromState ---$event--> $toState"
    }
  }


  abstract inner class TransitionAction(val action: Action) {
    abstract suspend fun execute(transition: Transition): Job?
  }

  inner class DepartureAction(
    val fromState: State,
    val toState: State? = null,
    val event: Event? = null,
    action: Action
  ) : TransitionAction(action) {
    override suspend fun execute(transition: Transition): Job? {
      if ((toState == null || toState == transition.toState) && (event == null || event == transition.event)) {
        return launch(context) {
          action(transition)
        }
      } else {
        return null
      }
    }
  }

  inner class ArrivalAction(
    val toState: State,
    val fromState: State? = null,
    val event: Event? = null,
    action: Action
  ) :
    TransitionAction(action) {
    override suspend fun execute(transition: Transition): Job? {
      if ((fromState == null || fromState == transition.fromState) && (event == null || event == transition.event)) {
        return launch(context) {
          action(transition)
        }
      } else {
        return null
      }
    }
  }

  inner class EventAction(
    val event: Event,
    val fromState: State? = null,
    val toState: State? = null,
    action: Action
  ) :
    TransitionAction(action) {
    override suspend fun execute(transition: Transition): Job? {
      if ((toState == null || toState == transition.toState) && (fromState == null || fromState == transition.fromState)) {
        return launch(context) {
          action(transition)
        }
      } else {
        return null
      }
    }
  }


  internal var _tt: TransitionTemplate? = null

  inner class TransitionTemplate(
    var fromState: State? = null,
    var toState: State? = null,
    var event: Event? = null,
    var condition: Condition? = null
  ) {
    fun generate() {
      addTransition(
        fromState ?: throw Exception("incomplete transition (from)"),
        toState ?: throw Exception("incomplete transition (to)"),
        event ?: throw Exception("incomplete transition (via)"),
        condition = condition
      )
      _tt = null
    }

  }

  val transition: TransitionTemplate
    get() {
      _tt?.generate()
      _tt = TransitionTemplate()
      return _tt!!
    }

  infix fun TransitionTemplate.from(state: State): TransitionTemplate {
    this.fromState = state; return this
  }

  infix fun TransitionTemplate.to(state: State): TransitionTemplate {
    this.toState = state; return this
  }

  infix fun TransitionTemplate.via(event: Event): TransitionTemplate {
    this.event = event; return this
  }

  infix fun TransitionTemplate.by(event: Event) = via(event)

  infix fun TransitionTemplate.check(condition: Condition): TransitionTemplate {
    this.condition = condition; return this
  }


  enum class ActionKind { ON_ARRIVAL, ON_DEPARTURE, ON_EVENT }

  internal var _at: ActionTemplate? = null

  inner class ActionTemplate(
    private val kind: ActionKind,
    var fromState: State? = null,
    var toState: State? = null,
    var event: Event? = null
  ) {

    fun generate(action: Action) {
      _tt?.generate()

      when (kind) {
        ActionKind.ON_ARRIVAL -> onArrivalAt(
          toState ?: throw Exception("incomplete action (at)"),
          fromState,
          event,
          action
        )
        ActionKind.ON_DEPARTURE -> onDepartureFrom(
          fromState ?: throw Exception("incomplete action (from)"),
          toState,
          event,
          action
        )
        ActionKind.ON_EVENT -> onEvent(
          event ?: throw Exception("incomplete action (from)"),
          toState,
          fromState,
          action
        )
      }

      _at = null
    }
  }

  val arriving: ActionTemplate
    get() {
      if (_at != null) throw Exception("previous action is missing run block")
      _at = ActionTemplate(ActionKind.ON_ARRIVAL)
      return _at!!
    }
  val departing: ActionTemplate
    get() {
      if (_at != null) throw Exception("previous action is missing run block")
      _at = ActionTemplate(ActionKind.ON_DEPARTURE)
      return _at!!
    }
  val receiving: ActionTemplate
    get() {
      if (_at != null) throw Exception("previous action is missing run block")
      _at = ActionTemplate(ActionKind.ON_EVENT)
      return _at!!
    }

  infix fun ActionTemplate.at(state: State): ActionTemplate {
    this.toState = state; return this
  }

  infix fun ActionTemplate.to(state: State) = at(state)

  infix fun ActionTemplate.from(state: State): ActionTemplate {
    this.fromState = state; return this
  }

  infix fun ActionTemplate.via(event: Event): ActionTemplate {
    this.event = event; return this
  }

  infix fun ActionTemplate.of(event: Event) = via(event)

  infix fun ActionTemplate.by(event: Event) = via(event)

  infix fun ActionTemplate.run(action: Action) {
    generate(action)
  }

}


fun StateMaschine(context: CoroutineContext = Dispatchers.Default, init: StateMaschine.() -> Unit): StateMaschine {
  val sm = StateMaschine(context)
  sm.init()
  sm._tt?.generate()
  if (sm._at != null) throw Exception("last action is missing run block")
  return sm
}
