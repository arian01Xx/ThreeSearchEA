//MEJORAR
//AGREGAR MAS INDICADORES PARA EVITAR ORDENES INFINITAS
#include <Trade/Trade.mqh>

CTrade trade;

input ENUM_TIMEFRAMES timeframe=PERIOD_M5;
double ask;
double bid;
double lots=0.1;
double actualPrice;
int Rsi;
double RSI[], RSIvalue;

int OnInit(){
  
   //RSI
   Rsi=iRSI(_Symbol,timeframe,14,PRICE_CLOSE);
   ArraySetAsSeries(RSI,true);

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason){

}

void OnTick(){
   //El estado inicial debe ser segun yo el precio actual del mercado?
   actualPrice = iClose(_Symbol, timeframe, 0);
   
   //lo que se invoca es el algoritmo central, el resto no
   int root_state=GetInitialState();
   Node* best_move = MCTS(root_state);
   
   //EMPEZAMOS
   ApplyAction(root_state,best_move.state);
}

int GetInitialState(){
  //El estado inicial indicas el integral que va a considerar evaluar
  //y las condiciones de lo que significa tal integral en cierto nivel
  //siempre deben ser indicadores?
  CopyBuffer(Rsi,0,0,1,RSI);
  RSIvalue=NormalizeDouble(RSI[0],_Digits);
  
  if(RSIvalue>70){
    //Estado de sobrecompra
    return 1; //Considerar vender
  }else if(RSIvalue<30){
    //Estado de sobreventa
    return 0; //Considerar comprar
  }else{
    //Estado neutral
    return 2; //No hacer nada o estado neutral
  }
}

//IMPLEMENTACION DEL MONTE CARLO TREE SEARCH
class Node{
public:

  int state;
  double wins;
  int visits;
  Node* parent;
  Node* children[];
  int num_children;
  
  Node(int state, Node* parent=NULL){
    this.state=state;
    this.wins=0;
    this.visits=0;
    this.parent=parent;
    this.num_children=0;
  }
  
  void AddChild(Node* child){
    ArrayResize(children, num_children+1);
    children[num_children++]=child;
  }
};

//FUNCION PRINCIPAL DE MCTS
Node* MCTS(int root_state){
  Node* root= new Node(root_state);
  for(int i=0; i<1000; i++){
    Node* node=Select(root);
    if(!IsTerminal(node.state)){
      Expand(node);
      node=node.children[0]; //Select the first child
    }
    double result=Simulate(node);
    Backpropagate(node, result);
  }
  return BestChild(root);
}

Node* Select(Node* node){
  while(node.num_children>0){
    node=BestUCT(node);
  }
  return node;
}

//ESTO VA PRIMERO QUE EXPAND y MCTS
int IsTerminal(int state){
  //Define your game terminal state logic here
  //Return 1 if the state is terminal, otherwise 0
  double profits=AccountInfoDouble(ACCOUNT_BALANCE);
  if(profits < 100000.0){
    return 0;
  }else{
    return 1;
  }
}

//DENTRO DE MCTS
void Expand(Node* node){
  int possible_actions[];
  GetPossibleActions(node.state, possible_actions);
  for(int i=0; i<ArraySize(possible_actions); i++){
    int new_state=ApplyAction(node.state, possible_actions[i]);
    Node* child=new Node(new_state, node);
    node.AddChild(child);
  }
}

//ESTO SE GUARDA EN RESULT
//DENTRO DE MCTS
double Simulate(Node* node){
  int state=node.state;
  while(!IsTerminal(state)){
    int possible_actions[];
    GetPossibleActions(state,possible_actions);
    int action=RolloutPolicy(possible_actions);
    state=ApplyAction(state, action);
  }
  return Result(state);
}

//DESPUES DEL RESULT VA ESTO Y DENTRO MCTS
void Backpropagate(Node* node, double result){
  while(node != NULL){
    node.visits++;
    node.wins+=result;
    node=node.parent;
  }
}

//DESPUES DE BACKPROPAGATE VA ESTO Y DENTRO DE MCTS
Node* BestChild(Node* node){
  Node* best_child=NULL;
  double best_value= -DBL_MAX;
  for(int i=0; i<node.num_children; i++){
    Node* child= node.children[i];
    double value=child.wins/child.visits;
    if(value>best_value){
      best_value=value;
      best_child=child;
    }
  }
  return best_child;
}

//pasar por referencia es agregarle & antes del nombre de la variable
//DENTRO DE SIMULATE
int RolloutPolicy(int &actions[]){
  return actions[MathRand() % ArraySize(actions)];
}

//DENTRO DE SIMULATE
double Result(int state){

  //aqui se condicia como el juego juzga sus ganancias
  //1 para victoria
  //0 para derrota
  //0.5 para empate
  //en este caso...
  double balance=AccountInfoDouble(ACCOUNT_BALANCE);
  if(balance>=100000.0){
    return 1.0;
  }else if(balance<=90000.0){
    return 0.0;
  }else{
    return 0.5;
  }
}
 
//DENTRO DE SELECT
Node* BestUCT(Node* node){
  Node* best_child=NULL;
  double best_value= -DBL_MAX;
  for(int i=0; i<node.num_children; i++){
    Node* child=node.children[i];
    double uct_value=(child.wins/child.visits)+
                     sqrt(2*log(node.visits)/child.visits);
    if(uct_value>best_value){
      best_value=uct_value;
      best_child=child;
    }
  }
  return best_child;
}

//ESTO VA DENTRO DE EXPAND Y SIMULATE
void GetPossibleActions(int state, int &actions[]){
  //Define your game possible actions logic here
  //Return an array of possible actions
  //1= selling, 0=buying, 2=nothing
  ArrayResize(actions,3);
  actions[0]=0; //Buy
  actions[1]=1; //Sell
  actions[2]=2; //nothing
}

//DENTRO DE EXPAND Y SIMULATE
int ApplyAction(int state, int action){
  //Define your game action application logic here
  //Return the new state after applying the action
  //Las acciones a considerar para cierto estado X
  ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
  bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
  
  if(action==0){
     //Buying
     double sl = ask - 0.0005;
     double tp = ask+0.0005;
     bool result = trade.Buy(lots, _Symbol, ask, sl, tp);
     if(result) {
       Print("buy order executed successfully");
     } else {
       int error = GetLastError();
       Print("Error executing sell order: ", error);
       ResetLastError();
     }
   }else if(action==1){
     //Selling
     double sl = bid + 0.0005;
     double tp = bid-0.0005;
     bool result = trade.Sell(lots, _Symbol, bid, sl, tp);
     if(result){
       Print("sell order executed successfully");
     }else{
       int error = GetLastError();
       Print("Error executing buy order: ", error);
       ResetLastError();
     }
   }

  return state+1;
}