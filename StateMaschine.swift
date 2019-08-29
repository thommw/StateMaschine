
protocol State: Equatable {
  var name: String { get }
}

extension State {
  var debugDescription: String { get { return "state \(name)" } }
}

protocol Event: Hashable {
  var name: String { get }
}

extension Event {
  var debugDescription: String { get { return "event \(name)" } }
}

protocol TransitionAction {
  associatedtype S: State
  associatedtype E: Event
  func execute(transition: StateMaschine<S, E>.Transition)
}

fileprivate let DEBUG = true

enum StateMaschineErrors: Error {
  case GeneralError(_ message: String)
}


class StateMaschine<S: State, E: Event> {
  
  typealias Condition = (Transition) -> Bool

  typealias Action = (Transition) -> Void

  private var stateNodes = [StateNode]()
  
  private var rootStateNode: StateNode?
  
  private var currentStateNode: StateNode?
  
  private var eventActions = [EventAction]()
  
  var currentState: S? {
    get {
      return currentStateNode?.state
    }
  }
  
  var eventQueue: DispatchQueue?
  
  func addTransition(fromState: S, toState: S, events: E..., condition: Condition? = nil) throws {
    if events.isEmpty { throw StateMaschineErrors.GeneralError("must specify an event") }
    
    for event in events {
      var fromStateNode = stateNodes.first { return $0.state == fromState }
      if fromStateNode == nil {
        if rootStateNode != nil { throw StateMaschineErrors.GeneralError("fromState not found") }
        
        fromStateNode = StateNode(fromState)
        stateNodes.append(fromStateNode!)
        rootStateNode = fromStateNode
      }
      
      let transition = Transition(fromState, toState, event, condition)
      var transitions = fromStateNode?.events[event]
      if transitions == nil {
        fromStateNode?.events[event] = [transition]
      } else {
        transitions?.append(transition)
      }
      
      let toStateNode = stateNodes.first { $0.state == toState }
      if toStateNode == nil {
        stateNodes.append(StateNode(toState))
      }
    }
  }
  
  
  func onDepartureFrom(fromState: S, toState: S?, event: E?, action: @escaping Action) throws {
    guard let fromStateNode = stateNodes.first(where: { $0.state == fromState }) else {
      throw StateMaschineErrors.GeneralError("state not found: \(fromState.name)")
    }
    fromStateNode.departureActions.append(DepartureAction(fromState, toState, event, action))
  }
  
  func onArrivalAt(toState: S, fromState: S?, event: E?, action: @escaping Action) throws {
    guard let toStateNode = stateNodes.first(where: { $0.state == toState }) else {
      throw StateMaschineErrors.GeneralError("state not found: \(toState.name)")
    }
    toStateNode.arrivalActions.append(ArrivalAction(toState, fromState, event, action))
  }
  
  func onEvent(event: E, fromState: S?, toState: S?, action: @escaping Action) throws {
    eventActions.append(EventAction(event, fromState, toState, action))
  }
  
  
  func start(startState: S? = nil) throws {
    guard (currentStateNode == nil) else {
      throw StateMaschineErrors.GeneralError("state machine already running")
    }
    
    if let startState = startState {
      currentStateNode = stateNodes.first { $0.state == startState }
      guard currentStateNode != nil else {
        throw StateMaschineErrors.GeneralError("start state not found: \(startState)")
      }
    } else {
      currentStateNode = rootStateNode
      guard currentStateNode != nil else {
        throw StateMaschineErrors.GeneralError("state machine not configured")
      }
    }
    
    self.eventQueue = DispatchQueue(label: "StateMaschineEvents", qos: .background)

    if DEBUG { print("state maschine started") }
  }
  
  
  func signal(event: E) {
    if DEBUG { print("received event \(event)") }
    eventQueue?.async {
      if let csn = self.currentStateNode {
        if let transitions = csn.events[event] {
          for transition in transitions {
            if transition.isValid() {
              if DEBUG { print("transitioning to state \(transition.toState)") }
              for action in self.eventActions.filter({ $0.event == event }) {
                action.execute(transition: transition)
              }
              
              for action in csn.departureActions {
                action.execute(transition: transition)
              }
              
              self.currentStateNode = self.stateNodes.first { $0.state == transition.toState }
              
              for action in self.currentStateNode!.arrivalActions {
                action.execute(transition: transition)
              }
              
              break // only process the first valid transition
            }
          }
        }
      }
    }
  }
  
  static func >>> (lhs: E, rhs: StateMaschine<S, E>) {
    rhs.signal(event: lhs)
  }
  
  class StateNode: Equatable {
    let state: S
    init(_ state: S) {
      self.state = state
    }
    var events = [E:[Transition]]()
    var departureActions = [DepartureAction]()
    var arrivalActions = [ArrivalAction]()
    
    static func == (lhs: StateNode, rhs: StateNode) -> Bool {
      return lhs.state == rhs.state
    }
  }
  
  
  class Transition {
    let fromState: S
    let toState: S
    let event: E
    let condition: Condition?
    
    init(_ fromState: S, _ toState: S, _ event: E, _ condition: Condition? = nil) {
      self.toState = toState
      self.fromState = fromState
      self.event = event
      self.condition = condition
    }
    
    func isValid() -> Bool {
      return condition?(self) ?? true
    }
  }
  
  
  class DepartureAction: TransitionAction {
    let fromState: S
    let toState: S?
    let event: E?
    var action: Action
    
    init(_ fromState: S, _ toState: S? = nil, _ event: E? = nil, _ action: @escaping Action) {
      self.fromState = fromState
      self.toState = toState
      self.event = event
      self.action = action
    }
    
    func execute(transition: Transition) {
      if ((toState == nil || toState?.name == transition.toState.name) &&
        (event == nil || event == transition.event)) {
        action(transition)
      }
    }
  }
  
  
  class ArrivalAction: TransitionAction {
    let fromState: S?
    let toState: S
    let event: E?
    var action: Action

    init(_ toState: S, _ fromState: S? = nil, _ event: E? = nil, _ action: @escaping Action) {
      self.fromState = fromState
      self.toState = toState
      self.event = event
      self.action = action
    }
    
    func execute(transition: Transition) {
      if ((fromState == nil || fromState == transition.fromState) &&
        (event == nil || event == transition.event)) {
        action(transition)
      }
    }
  }
  
  
  class EventAction: TransitionAction {
    let fromState: S?
    let toState: S?
    let event: E
    var action: Action

    init(_ event: E, _ fromState: S? = nil, _ toState: S? = nil, _ action: @escaping Action) {
      self.fromState = fromState
      self.toState = toState
      self.event = event
      self.action = action
    }
    
    func execute(transition: Transition) {
      if ((toState == nil || toState == transition.toState) &&
        (fromState == nil || fromState == transition.fromState)) {
        action(transition)
      }
    }
  }


  class TransitionTemplate {
    let sm: StateMaschine<S, E>
    var fromState: S?
    var toState: S?
    var event: E?
    var condition: Condition?
    
    init(sm: StateMaschine<S, E>, fromState: S) {
      self.sm = sm
      self.fromState = fromState
    }
    
    @discardableResult
    static func >>> (lhs: TransitionTemplate, rhs: E) -> TransitionTemplate {
      lhs.event = rhs
      return lhs
    }
    
    @discardableResult
    static func >>> (lhs: TransitionTemplate, rhs: S) -> TransitionTemplate {
      lhs.toState = rhs
      return lhs
    }
    
    static func ??? (lhs: TransitionTemplate, rhs: Condition?) {
      lhs.condition = rhs
      lhs.generate()
    }
    
    func generate() {
      try? sm.addTransition(fromState: fromState!, toState: toState!, events: event!, condition: condition)
    }
  }
  
  static func =+ (lhs: StateMaschine<S, E>, rhs: S) -> TransitionTemplate {
    return TransitionTemplate(sm: lhs, fromState: rhs)
  }
  

  class ActionTemplate {
    enum ActionKind { case ON_ARRIVAL, ON_DEPARTURE, ON_EVENT }
    
    let kind: ActionKind
    let sm: StateMaschine<S, E>
    var fromState: S?
    var toState: S?
    var event: E?
    var action: Action?

    init(sm: StateMaschine<S, E>, kind: ActionKind, fromState: S? = nil, toState: S? = nil, event: E? = nil) {
      self.sm = sm
      self.kind = kind
      self.fromState = fromState
      self.toState = toState
      self.event = event
    }
    
    @discardableResult
    static func >>> (lhs: ActionTemplate, rhs: S) -> ActionTemplate {
      if lhs.toState == nil {
        lhs.toState = rhs
      } else {
        lhs.fromState = rhs
      }
      return lhs
    }
    
    @discardableResult
    static func <<< (lhs: ActionTemplate, rhs: S) -> ActionTemplate {
      lhs.fromState = rhs
      return lhs
    }
    
    @discardableResult
    static func >>> (lhs: ActionTemplate, rhs: E) -> ActionTemplate {
      lhs.event = rhs
      return lhs
    }
    
    static func !!! (lhs: ActionTemplate, rhs: @escaping Action) {
      lhs.action = rhs
      lhs.generate(action: rhs)
    }
    
    func generate(action: @escaping Action) {
      switch kind {
      case .ON_DEPARTURE:
        try? sm.onDepartureFrom(fromState: fromState!, toState: toState, event: event, action: action)
      case .ON_ARRIVAL:
        try? sm.onArrivalAt(toState: toState!, fromState: fromState, event: event, action: action)
      case .ON_EVENT:
        try? sm.onEvent(event: event!, fromState: fromState, toState: toState, action: action)
      }
    }
  }
  
  static func => (lhs: StateMaschine<S, E>, rhs: S) -> ActionTemplate {
    return ActionTemplate(sm: lhs, kind: .ON_DEPARTURE, fromState: rhs)
  }
  
  static func =< (lhs: StateMaschine<S, E>, rhs: S) -> ActionTemplate {
    return ActionTemplate(sm: lhs, kind: .ON_ARRIVAL, toState: rhs)
  }
  
  static func =! (lhs: StateMaschine<S, E>, rhs: E) -> ActionTemplate {
    return ActionTemplate(sm: lhs, kind: .ON_EVENT, event: rhs)
  }
}

infix operator =+  : AdditionPrecedence
infix operator >>> : AdditionPrecedence
infix operator <<< : AdditionPrecedence
infix operator ??? : AdditionPrecedence
infix operator !!! : AdditionPrecedence
infix operator =>  : AdditionPrecedence
infix operator =<  : AdditionPrecedence
infix operator =!  : AdditionPrecedence

func foobar() {
  
  enum TestEvent: String, Event {
    var name: String {
      get { return self.rawValue }
    }
    
    case START, STOP
  }
  
  enum TestState: String, State {
    var name: String {
      get { return self.rawValue }
    }
    
    case STOPPED, STARTED
  }
  
  let sm = StateMaschine<TestState, TestEvent>()
  sm =+ TestState.STARTED >>> TestEvent.START >>> TestState.STOPPED ??? { _ in return true }
  sm =+ TestState.STARTED >>> TestEvent.STOP >>> TestState.STOPPED ??? nil
  
  sm => TestState.STOPPED >>> TestEvent.START >>> TestState.STARTED !!! { _ in }
  sm =< TestState.STARTED !!! { _ in }
  sm =! TestEvent.START !!! { _ in }
 
}


/*
 
 
 protocol State {
 var name: String { get }
 }
 
 protocol Event {
 var name: String { get }
 }
 
 typealias Condition = (Transition) -> Bool
 
 typealias Action = (Transition) -> Void
 
 enum StateMaschineErrors: Error {
 case GeneralError(String)
 }
 
 
 class StateMaschine {
 
 class STATE_MASCHINE_START_CLASS: Event {
 var name: String {
 get {
 return "STATE_MASCHINE_START"
 }
 }
 }
 
 static let STATE_MASCHINE_START: Event = STATE_MASCHINE_START_CLASS()
 
 class STATE_MASCHINE_INITIAL_CLASS: State {
 var name: String {
 get {
 return "STATE_MASCHINE_INITIAL"
 }
 }
 }
 
 static let STATE_MASCHINE_INITIAL: State = STATE_MASCHINE_INITIAL_CLASS()
 
 private var stateNodes = [StateNode]()
 
 private var rootStateNode: StateNode?
 
 private var currentStateNode: StateNode?
 
 private var eventActions = [EventAction]()
 
 var currentState: State? {
 get {
 return currentStateNode?.state
 }
 }
 
 func addTransition(fromState: State, toState: State, events: Event..., condition: Condition? = nil) throws {
 if events.isEmpty { throw StateMaschineErrors.GeneralError("must specify an event") }
 
 for event in events {
 var fromStateNode = stateNodes.first { return $0.state.name == fromState.name }
 if fromStateNode == nil {
 if rootStateNode != nil { throw StateMaschineErrors.GeneralError("fromState not found") }
 
 fromStateNode = StateNode(fromState)
 stateNodes.append(fromStateNode!)
 rootStateNode = fromStateNode
 }
 
 let transition = Transition(fromState, toState, event, condition)
 var transitions = fromStateNode?.events[event.name]
 if transitions == nil {
 fromStateNode?.events[event.name] = [transition]
 } else {
 transitions?.append(transition)
 }
 
 let toStateNode = stateNodes.first { $0.state.name == toState.name }
 if toStateNode == nil {
 stateNodes.append(StateNode(toState))
 }
 }
 }
 
 
 func onDepartureFrom(fromState: State, toState: State?, event: Event?, action: @escaping Action) throws {
 guard var fromStateNode = stateNodes.first(where: { $0.state.name == fromState.name }) else {
 throw StateMaschineErrors.GeneralError("state not found: \(fromState.name)")
 }
 fromStateNode.departureActions.append(DepartureAction(fromState, toState, event, action))
 }
 
 func onArrivalAt(toState: State, fromState: State?, event: Event?, action: @escaping Action) throws {
 guard var toStateNode = stateNodes.first(where: { $0.state.name == toState.name }) else {
 throw StateMaschineErrors.GeneralError("state not found: \(toState.name)")
 }
 toStateNode.arrivalActions.append(ArrivalAction(toState, fromState, event, action))
 }
 
 func onEvent(event: Event, fromState: State?, toState: State?, action: @escaping Action) throws {
 eventActions.append(EventAction(event, fromState, toState, action))
 }
 
 
 
 
 }
 
 
 struct StateNode: Equatable {
 let state: State
 init(_ state: State) {
 self.state = state
 }
 var events = [String:[Transition]]()
 fileprivate var departureActions = [DepartureAction]()
 fileprivate var arrivalActions = [ArrivalAction]()
 
 static func == (lhs: StateNode, rhs: StateNode) -> Bool {
 return lhs.state.name == rhs.state.name
 }
 }
 
 
 struct Transition {
 let fromState: State
 let toState: State
 let event: Event
 let condition: Condition?
 
 init(_ fromState: State, _ toState: State, _ event: Event, _ condition: Condition? = nil) {
 self.toState = toState
 self.fromState = fromState
 self.event = event
 self.condition = condition
 }
 
 func isValid() -> Bool {
 return condition?(self) ?? true
 }
 }
 
 
 protocol TransitionAction {
 func execute(transition: Transition)
 }
 
 private class AbstractTransitionAction {
 let fromState: State?
 let toState: State?
 let event: Event?
 var action: Action
 
 init(_ fromState: State?, _ toState: State? = nil, _ event: Event? = nil, _ action: @escaping Action) {
 self.fromState = fromState
 self.toState = toState
 self.event = event
 self.action = action
 }
 }
 
 private class DepartureAction: AbstractTransitionAction, TransitionAction {
 
 init(_ fromState: State, _ toState: State? = nil, _ event: Event? = nil, _ action: @escaping Action) {
 super.init(fromState, toState, event, action)
 }
 
 func execute(transition: Transition) {
 if ((toState == nil || toState?.name == transition.toState.name) &&
 (event == nil || event?.name == transition.event.name)) {
 action(transition)
 }
 }
 }
 
 
 private class ArrivalAction: AbstractTransitionAction {
 
 init(_ toState: State, _ fromState: State? = nil, _ event: Event? = nil, _ action: @escaping Action) {
 super.init(fromState, toState, event, action)
 }
 
 func execute(transition: Transition) {
 if ((fromState == nil || fromState?.name == transition.fromState.name) &&
 (event == nil || event?.name == transition.event.name)) {
 action(transition)
 }
 }
 }
 
 
 private class EventAction: AbstractTransitionAction {
 
 init(_ event: Event, _ fromState: State? = nil, _ toState: State? = nil, _ action: @escaping Action) {
 super.init(fromState: fromState, toState: toState, event: event, action: action)
 }
 
 func execute(transition: Transition) {
 if ((toState == nil || toState?.name == transition.toState.name) &&
 (fromState == nil || fromState?.name == transition.fromState.name)) {
 action(transition)
 }
 }
 }
 
 
 */
