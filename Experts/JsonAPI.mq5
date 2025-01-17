//+------------------------------------------------------------------+
//
// Copyright (C) 2019 Nikolai Khramkov
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
//+------------------------------------------------------------------+

// TODO: Experation
// TODO: Deviation
// TODO: Fetch trades

#property copyright   "Copyright 2019, Nikolai Khramkov."
#property link        "https://github.com/khramkov"
#property version     "1.20"
#property description "MQL5 JSON API"
#property description "See github link for documentation" 

#include <Trade/AccountInfo.mqh>
#include <Trade/Trade.mqh>
#include <Zmq/Zmq.mqh>
#include <Json.mqh>

string HOST="*";
int SYS_PORT=15555;
int DATA_PORT=15556;
int LIVE_PORT=15557;
int STR_PORT=15558;

// ZeroMQ Cnnections
Context context("MQL5 JSON API");
Socket sysSocket(context,ZMQ_REP);
Socket dataSocket(context,ZMQ_PUSH);
Socket liveSocket(context,ZMQ_PUSH);
Socket streamSocket(context,ZMQ_PUSH);

// Global variables
bool debug = true;
bool liveStream = true;
bool connectedFlag= true;
datetime lastBar = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit(){
   /* Bindinig ZMQ ports on init */
   
   // OnTimer() function event genegation - 1 millisecond
   EventSetMillisecondTimer(1);
   
   sysSocket.bind(StringFormat("tcp://%s:%d",HOST,SYS_PORT));
   dataSocket.bind(StringFormat("tcp://%s:%d",HOST,DATA_PORT));
   liveSocket.bind(StringFormat("tcp://%s:%d",HOST,LIVE_PORT));
   streamSocket.bind(StringFormat("tcp://%s:%d",HOST,STR_PORT));
   
   Print("Binding 'System' socket on port "+IntegerToString(SYS_PORT)+"...");
   Print("Binding 'Data' socket on port "+IntegerToString(DATA_PORT)+"...");
   Print("Binding 'Live' socket on port "+IntegerToString(LIVE_PORT)+"...");
   Print("Binding 'Streaming' socket on port "+IntegerToString(STR_PORT)+"...");

   sysSocket.setLinger(1000);
   dataSocket.setLinger(1000);
   liveSocket.setLinger(1000);
   streamSocket.setLinger(1000);

   // Number of messages to buffer in RAM.
   sysSocket.setSendHighWaterMark(1);
   dataSocket.setSendHighWaterMark(5);
   liveSocket.setSendHighWaterMark(1);
   streamSocket.setSendHighWaterMark(50);

   return(INIT_SUCCEEDED);
}
  
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason){
   /* Unbinding ZMQ ports on denit */
   
   Print(__FUNCTION__," Deinitialization reason code = ",reason); 
   
   sysSocket.unbind(StringFormat("tcp://%s:%d",HOST,SYS_PORT));
   dataSocket.unbind(StringFormat("tcp://%s:%d",HOST,DATA_PORT));
   liveSocket.unbind(StringFormat("tcp://%s:%d",HOST,LIVE_PORT));
   streamSocket.unbind(StringFormat("tcp://%s:%d",HOST,STR_PORT));
   
   Print("Unbinding 'System' socket on port "+IntegerToString(SYS_PORT)+"..");
   Print("Unbinding 'Data' socket on port "+IntegerToString(DATA_PORT)+"..");
   Print("Unbinding 'Live' socket on port "+IntegerToString(LIVE_PORT)+"..");
   Print("Unbinding 'Streaming' socket on port "+IntegerToString(STR_PORT)+"...");
}
  
//+------------------------------------------------------------------+
//| Expert timer function                                            |
//+------------------------------------------------------------------+
void OnTimer(){

   ZmqMsg request;
   
   // If liveStream == true, push last candle to liveSocket. 
   if(liveStream){
   
       CJAVal candle, last;
      
      // Check if terminal connected to market
      if(TerminalInfoInteger(TERMINAL_CONNECTED)){
      
            datetime thisBar=(datetime)SeriesInfoInteger(_Symbol,_Period,SERIES_LASTBAR_DATE);
            if(lastBar!=thisBar){
               
               MqlRates rates[1];
              
               if(CopyRates(_Symbol,_Period,1,1,rates)!=1) { /*error processing */ };
               
               candle[0] = (long) rates[0].time;
               candle[1] = (double) rates[0].open;
               candle[2] = (double) rates[0].high;
               candle[3] = (double) rates[0].low;
               candle[4] = (double) rates[0].close;
               candle[5] = (double) rates[0].tick_volume;
               // skip sending data on script init when lastBar == 0 
               if(lastBar!=0){
                  last["status"] = (string) "CONNECTED";
                  last["data"].Set(candle);
                  string t=last.Serialize();
                  if(debug) Print(t);
                  InformClientSocket(liveSocket,t);
               }
  
               lastBar=thisBar;
            }
            connectedFlag=true; 
      } 
      //If disconnected from market
      else {
         // send disconnect message only once
         if(connectedFlag){
            last["status"] = (string) "DISCONNECTED";
            string t=last.Serialize();
            if(debug) Print(t);
            InformClientSocket(liveSocket,t);
            connectedFlag=false;
         }
      }
   }
   
   // Get request from client via System socket.
   sysSocket.recv(request,true);
   
   // Request recived
   if(request.size()>0){ 
      // Pull request to RequestHandler().
      RequestHandler(request);
   }
}
  
//+------------------------------------------------------------------+
//| Request handler                                                  |
//+------------------------------------------------------------------+
void RequestHandler(ZmqMsg &request){

   CJAVal message;
         
   ResetLastError();
   // Get data from reguest
   string msg=request.getData();
   
   if(debug) Print("Processing:"+msg);
   
   // Deserialize msg to CJAVal array
   if(!message.Deserialize(msg)){
      ActionDoneOrError(65537, __FUNCTION__);
      Alert("Deserialization Error");
      ExpertRemove();
   }
   // Send response to System socket that request was received
   // Some historical data requests can take a lot of time
   InformClientSocket(sysSocket, "OK");
   
   // Process action command
   string action = message["action"].ToStr();
   
   if(action=="CONFIG")          {ScriptConfiguration(message);}
   else if(action=="ACCOUNT")    {GetAccountInfo();}
   else if(action=="BALANCE")    {GetBalanceInfo();}
   else if(action=="HISTORY")    {HistoryInfo(message);}
   else if(action=="TRADE")      {TradingModule(message);}
   else if(action=="POSITIONS")  {GetPositions(message);}
   else if(action=="ORDERS")     {GetOrders(message);}
   // Action command error processing
   else ActionDoneOrError(65538, __FUNCTION__);
   
}
  
//+------------------------------------------------------------------+
//| Reconfigure the script params                                    |
//+------------------------------------------------------------------+
void ScriptConfiguration(CJAVal &dataObject){
  
   string symb=dataObject["symbol"].ToStr();
   ENUM_TIMEFRAMES tf=GetTimeframe(dataObject["chartTF"].ToStr());
   
   // If the symbol and(or) TF are different from the chart values
   if(!(tf == _Period & symb == _Symbol)){
      // Check if symbol exists
      if(SymbolInfoInteger(symb, SYMBOL_EXIST)){  
         // Set chart symbol and TF
         if(ChartSetSymbolPeriod(0, symb, tf))
            // All done
            ActionDoneOrError(ERR_SUCCESS, __FUNCTION__);  
            
         // Error Handling     
         else ActionDoneOrError(ERR_MARKET_WRONG_PROPERTY, __FUNCTION__);
      }
      else ActionDoneOrError(ERR_MARKET_UNKNOWN_SYMBOL, __FUNCTION__);
   }
   // Nothing to change
   else ActionDoneOrError(ERR_SUCCESS, __FUNCTION__);
}

//+------------------------------------------------------------------+
//| Account information                                              |
//+------------------------------------------------------------------+
void GetAccountInfo(){
  
   CJAVal info;
   
   info["error"] = false;
   info["broker"] = AccountInfoString(ACCOUNT_COMPANY);
   info["currency"] = AccountInfoString(ACCOUNT_CURRENCY);
   info["server"] = AccountInfoString(ACCOUNT_SERVER); 
   info["trading_allowed"] = TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
   info["bot_trading"] = AccountInfoInteger(ACCOUNT_TRADE_EXPERT);   
   info["balance"] = AccountInfoDouble(ACCOUNT_BALANCE);
   info["equity"] = AccountInfoDouble(ACCOUNT_EQUITY);
   info["margin"] = AccountInfoDouble(ACCOUNT_MARGIN);
   info["margin_free"] = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   info["margin_level"] = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   
   string t=info.Serialize();
   if(debug) Print(t);
   InformClientSocket(dataSocket,t);
}

//+------------------------------------------------------------------+
//| Balance information                                              |
//+------------------------------------------------------------------+
void GetBalanceInfo(){  
      
   CJAVal info;
   info["balance"] = AccountInfoDouble(ACCOUNT_BALANCE);
   info["equity"] = AccountInfoDouble(ACCOUNT_EQUITY);
   info["margin"] = AccountInfoDouble(ACCOUNT_MARGIN);
   info["margin_free"] = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   
   string t=info.Serialize();
   //if(debug) Print(t);
   InformClientSocket(dataSocket,t);
}

//+------------------------------------------------------------------+
//| Get historical data                                              |
//+------------------------------------------------------------------+
void HistoryInfo(CJAVal &dataObject){ 
 
   string actionType = dataObject["actionType"].ToStr();
   if(actionType=="DATA"){
      CJAVal c, d;
      MqlRates r[];
      
      int copied;    
      string symbol=dataObject["symbol"].ToStr();
      ENUM_TIMEFRAMES period=GetTimeframe(dataObject["chartTF"].ToStr()); 
      datetime fromDate=(datetime)dataObject["fromDate"].ToInt();
      datetime toDate=TimeCurrent();
      if(dataObject["toDate"].ToInt()!=NULL) toDate=(datetime)dataObject["toDate"].ToInt();

      if(debug){
         Print("Fetching HISTORY");
         Print("1) Symbol:"+symbol);
         Print("2) Timeframe:"+EnumToString(period));
         Print("3) Date from:"+TimeToString(fromDate));
         if(dataObject["toDate"].ToInt()!=NULL)Print("4) Date to:"+TimeToString(toDate));
      }
       
      copied=CopyRates(symbol,period,fromDate,TimeCurrent(),r);
      if(copied){
         for(int i=0;i<copied;i++){
            c[i][0]=(long)   r[i].time;
            c[i][1]=(double) r[i].open;
            c[i][2]=(double) r[i].high;
            c[i][3]=(double) r[i].low;
            c[i][4]=(double) r[i].close;
            c[i][5]=(double) r[i].tick_volume;
         }
         d["data"].Set(c);
      }
      else {d["data"].Add(c);}
      
      string t=d.Serialize();
      //if(debug) Print(t);
      InformClientSocket(dataSocket,t);
   }
   
   else if(actionType=="TRADES"){
      
   }
    // Error wrong action type
   else ActionDoneOrError(65538, __FUNCTION__);
}

//+------------------------------------------------------------------+
//| Fetch positions information                               |
//+------------------------------------------------------------------+
void GetPositions(CJAVal &dataObject){  
   CPositionInfo myposition;
   CJAVal data, position;

   // Get positions  
   int positionsTotal=PositionsTotal();
   // Create empty array if no positions
   if(!positionsTotal) data["positions"].Add(position);
   // Go through positions in a loop
   for(int i=0;i<positionsTotal;i++){
      ResetLastError();
      
      if(myposition.Select(PositionGetSymbol(i))){
      
        position["id"]=PositionGetInteger(POSITION_IDENTIFIER);
        position["magic"]=PositionGetInteger(POSITION_MAGIC);
        position["symbol"]=PositionGetString(POSITION_SYMBOL);
        position["type"]=EnumToString(ENUM_POSITION_TYPE(PositionGetInteger(POSITION_TYPE)));
        position["time_setup"]=PositionGetInteger(POSITION_TIME);
        position["open"]=PositionGetDouble(POSITION_PRICE_OPEN);
        position["stoploss"]=PositionGetDouble(POSITION_SL);
        position["takeprofit"]=PositionGetDouble(POSITION_TP);
        position["volume"]=PositionGetDouble(POSITION_VOLUME);
      
        data["error"]=(bool) false;
        data["positions"].Add(position);
      }
       // Error handling    
      else ActionDoneOrError(ERR_TRADE_POSITION_NOT_FOUND, __FUNCTION__);
   }
   
   string t=data.Serialize();
   if(debug) Print(t);
   InformClientSocket(dataSocket,t);
}

//+------------------------------------------------------------------+
//| Fetch orders information                               |
//+------------------------------------------------------------------+
void GetOrders(CJAVal &dataObject){
   ResetLastError();
   
   COrderInfo myorder;
   CJAVal data, order;
   
   // Get orders
   if (HistorySelect(0,TimeCurrent())){    
      int ordersTotal = OrdersTotal();
      // Create empty array if no orders
      if(!ordersTotal) {data["error"]=(bool) false; data["orders"].Add(order);}
      
      for(int i=0;i<ordersTotal;i++){

         if (myorder.Select(OrderGetTicket(i))){   
            order["id"]=(string) myorder.Ticket();
            order["magic"]=OrderGetInteger(ORDER_MAGIC); 
            order["symbol"]=OrderGetString(ORDER_SYMBOL);
            order["type"]=EnumToString(ENUM_ORDER_TYPE(OrderGetInteger(ORDER_TYPE)));
            order["time_setup"]=OrderGetInteger(ORDER_TIME_SETUP);
            order["open"]=OrderGetDouble(ORDER_PRICE_OPEN);
            order["stoploss"]=OrderGetDouble(ORDER_SL);
            order["takeprofit"]=OrderGetDouble(ORDER_TP);
            order["volume"]=OrderGetDouble(ORDER_VOLUME_INITIAL);
            
            data["error"]=(bool) false;
            data["orders"].Add(order);
      } 
      // Error handling   
      else ActionDoneOrError(ERR_TRADE_ORDER_NOT_FOUND,  __FUNCTION__);
      }
   }
      
   string t=data.Serialize();
   if(debug) Print(t);
   InformClientSocket(dataSocket,t);
}

//+------------------------------------------------------------------+
//| Trading module                                                   |
//+------------------------------------------------------------------+
void TradingModule(CJAVal &dataObject){
   ResetLastError();
   CTrade trade;
   
   string   actionType = dataObject["actionType"].ToStr();
   string   symbol=dataObject["symbol"].ToStr();
   // Check if symbol the same
   if(!(symbol==_Symbol)) ActionDoneOrError(ERR_MARKET_UNKNOWN_SYMBOL, __FUNCTION__);
   
   int      idNimber=(int)dataObject["id"].ToInt();
   double   volume=dataObject["volume"].ToDbl();
   double   SL=dataObject["stoploss"].ToDbl();
   double   TP=dataObject["takeprofit"].ToDbl();
   double   price=NormalizeDouble(dataObject["price"].ToDbl(),_Digits);
   datetime expiration=TimeTradeServer()+PeriodSeconds(PERIOD_D1);
   double   deviation=dataObject["deviation"].ToDbl();  
   string   comment=dataObject["comment"].ToStr();
   
   // Market orders
   if(actionType=="ORDER_TYPE_BUY" || actionType=="ORDER_TYPE_SELL"){  
      ENUM_ORDER_TYPE orderType=(ENUM_ORDER_TYPE)actionType; 
      price = SymbolInfoDouble(symbol,SYMBOL_ASK);                                        
      if(orderType==ORDER_TYPE_SELL) price=SymbolInfoDouble(symbol,SYMBOL_BID);
      
      if(trade.PositionOpen(symbol,orderType,volume,price,SL,TP,comment)){
         OrderDoneOrError(false, __FUNCTION__, trade);
         return;
      }
     }
   
   // Pending orders
   else if(actionType=="ORDER_TYPE_BUY_LIMIT" || actionType=="ORDER_TYPE_SELL_LIMIT" || actionType=="ORDER_TYPE_BUY_STOP" || actionType=="ORDER_TYPE_SELL_STOP"){  
      if(actionType=="ORDER_TYPE_BUY_LIMIT"){
         if(trade.BuyLimit(volume,price,symbol,SL,TP,ORDER_TIME_GTC,expiration,comment)){
            OrderDoneOrError(false, __FUNCTION__, trade);
            return;
         }
      }
      else if(actionType=="ORDER_TYPE_SELL_LIMIT"){
         if(trade.SellLimit(volume,price,symbol,SL,TP,ORDER_TIME_GTC,expiration,comment)){
            OrderDoneOrError(false, __FUNCTION__, trade);
            return;
         }
      }
      else if(actionType=="ORDER_TYPE_BUY_STOP"){
         if(trade.BuyStop(volume,price,symbol,SL,TP,ORDER_TIME_GTC,expiration,comment)){
            OrderDoneOrError(false, __FUNCTION__, trade);
            return;
         }
      }
      else if (actionType=="ORDER_TYPE_SELL_STOP"){
         if(trade.SellStop(volume,price,symbol,SL,TP,ORDER_TIME_GTC,expiration,comment)){
            OrderDoneOrError(false, __FUNCTION__, trade);
            return;
         }
      }
    }
   // Position modify    
   else if(actionType=="POSITION_MODIFY"){
      if(trade.PositionModify(idNimber,SL,TP)){
         OrderDoneOrError(false, __FUNCTION__, trade);
         return;
      }
   }
   // Position close partial   
   else if(actionType=="POSITION_PARTIAL"){
      if(trade.PositionClosePartial(idNimber,volume)){
         OrderDoneOrError(false, __FUNCTION__, trade);
         return;
      }
   }
   // Position close by id       
   else if(actionType=="POSITION_CLOSE_ID"){
      if(trade.PositionClose(idNimber)){
         OrderDoneOrError(false, __FUNCTION__, trade);
         return;
      }
   }
   // Position close by symbol
   else if(actionType=="POSITION_CLOSE_SYMBOL"){
      if(trade.PositionClose(symbol)){
         OrderDoneOrError(false, __FUNCTION__, trade);
         return;
      }
   }
   // Modify pending order
   else if(actionType=="ORDER_MODIFY"){  
      if(trade.OrderModify(idNimber,price,SL,TP,ORDER_TIME_GTC,expiration)){
         OrderDoneOrError(false, __FUNCTION__, trade);
         return;
      }
  }
   // Cancel pending order  
   else if(actionType=="ORDER_CANCEL"){
      if(trade.OrderDelete(idNimber)){
         OrderDoneOrError(false, __FUNCTION__, trade);
         return;
      }
   }
   // Action type dosen't exist
   else ActionDoneOrError(65538, __FUNCTION__);
   
   // This part of the code runs if order was not completed
   OrderDoneOrError(true, __FUNCTION__, trade);
}

//+------------------------------------------------------------------+ 
//| TradeTransaction function                                        | 
//+------------------------------------------------------------------+ 
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result){
   
   ENUM_TRADE_TRANSACTION_TYPE  trans_type=trans.type;
   switch(trans.type) {
   
      // case  TRADE_TRANSACTION_POSITION: {}  break;
      // case  TRADE_TRANSACTION_DEAL_ADD: {}  break;
      case  TRADE_TRANSACTION_REQUEST:{
         CJAVal data, req, res;
         
         req["action"]=EnumToString(request.action);
         req["order"]=(int) request.order;
         req["symbol"]=(string) request.symbol;
         req["volume"]=(double) request.volume;
         req["price"]=(double) request.price;
         req["stoplimit"]=(double) request.stoplimit;
         req["sl"]=(double) request.sl;
         req["tp"]=(double) request.tp;
         req["deviation"]=(int) request.deviation;
         req["type"]=EnumToString(request.type);
         req["type_filling"]=EnumToString(request.type_filling);
         req["type_time"]=EnumToString(request.type_time);
         req["expiration"]=(int) request.expiration;
         req["comment"]=(string) request.comment;
         req["position"]=(int) request.position;
         req["position_by"]=(int) request.position_by;
         
         res["retcode"]=(int) result.retcode;
         res["result"]=(string) GetRetcodeID(result.retcode);
         res["deal"]=(int) result.order;
         res["order"]=(int) result.order;
         res["volume"]=(double) result.volume;
         res["price"]=(double) result.price;
         res["comment"]=(string) result.comment;
         res["request_id"]=(int) result.request_id;
         res["retcode_external"]=(int) result.retcode_external;

         data["request"].Set(req);
         data["result"].Set(res);
         
         string t=data.Serialize();
         if(debug) Print(t);
         InformClientSocket(streamSocket,t);
      }
      break;
      default: {} break;
   }
}

//+------------------------------------------------------------------+
//| Convetr chart timeframe from string to enum                      |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES GetTimeframe(string chartTF){

   ENUM_TIMEFRAMES tf;
   
   if(chartTF=="M1")       tf=PERIOD_M1;
   else if(chartTF=="M5")  tf=PERIOD_M5;
   else if(chartTF=="M15") tf=PERIOD_M15;
   else if(chartTF=="M30") tf=PERIOD_M30;
   else if(chartTF=="H1")  tf=PERIOD_H1;
   else if(chartTF=="H2")  tf=PERIOD_H2;
   else if(chartTF=="H3")  tf=PERIOD_H3;
   else if(chartTF=="H4")  tf=PERIOD_H4;
   else if(chartTF=="H6")  tf=PERIOD_H6;
   else if(chartTF=="H8")  tf=PERIOD_H8;
   else if(chartTF=="H12") tf=PERIOD_H12;
   else if(chartTF=="D1")  tf=PERIOD_D1;
   else if(chartTF=="W1")  tf=PERIOD_W1;
   else if(chartTF=="MN1") tf=PERIOD_MN1;
   //error will be raised in config function
   else tf=NULL;
   return(tf);
}
  
//+------------------------------------------------------------------+
//| Trade confirmation                                               |
//+------------------------------------------------------------------+
void OrderDoneOrError(bool error, string funcName, CTrade &trade){
   
   CJAVal conf;
   
   conf["error"]=(bool) error;
   conf["retcode"]=(int) trade.ResultRetcode();
   conf["desription"]=(string) GetRetcodeID(trade.ResultRetcode());
   // conf["deal"]=(int) trade.ResultDeal(); 
   conf["order"]=(int) trade.ResultOrder();
   conf["volume"]=(double) trade.ResultVolume();
   conf["price"]=(double) trade.ResultPrice();
   conf["bid"]=(double) trade.ResultBid();
   conf["ask"]=(double) trade.ResultAsk();
   conf["function"]=(string) funcName;
   
   string t=conf.Serialize();
   if(debug) Print(t);
   InformClientSocket(dataSocket,t);
}

//+------------------------------------------------------------------+
//| Action confirmation                                              |
//+------------------------------------------------------------------+
void ActionDoneOrError(int lastError, string funcName){
   
   CJAVal conf;
   
   conf["error"]=(bool)true;
   if(lastError==0) conf["error"]=(bool)false;
   
   conf["lastError"]=(string) lastError;
   conf["description"]=GetErrorID(lastError);
   conf["function"]=(string) funcName;
   
   string t=conf.Serialize();
   if(debug) Print(t);
   InformClientSocket(dataSocket,t);
}

//+------------------------------------------------------------------+
//| Inform Client via socket                                         |
//+------------------------------------------------------------------+
void InformClientSocket(Socket &workingSocket,string replyMessage){  
   
   // non-blocking
   workingSocket.send(replyMessage,true);   
   // TODO: Array out of range error
   ResetLastError();                                
}

//+------------------------------------------------------------------+
//| Get retcode message by retcode id                                |
//+------------------------------------------------------------------+   
string GetRetcodeID(int retcode){ 

   switch(retcode){ 
      case 10004: return("TRADE_RETCODE_REQUOTE");             break; 
      case 10006: return("TRADE_RETCODE_REJECT");              break; 
      case 10007: return("TRADE_RETCODE_CANCEL");              break; 
      case 10008: return("TRADE_RETCODE_PLACED");              break; 
      case 10009: return("TRADE_RETCODE_DONE");                break; 
      case 10010: return("TRADE_RETCODE_DONE_PARTIAL");        break; 
      case 10011: return("TRADE_RETCODE_ERROR");               break; 
      case 10012: return("TRADE_RETCODE_TIMEOUT");             break; 
      case 10013: return("TRADE_RETCODE_INVALID");             break; 
      case 10014: return("TRADE_RETCODE_INVALID_VOLUME");      break; 
      case 10015: return("TRADE_RETCODE_INVALID_PRICE");       break; 
      case 10016: return("TRADE_RETCODE_INVALID_STOPS");       break; 
      case 10017: return("TRADE_RETCODE_TRADE_DISABLED");      break; 
      case 10018: return("TRADE_RETCODE_MARKET_CLOSED");       break; 
      case 10019: return("TRADE_RETCODE_NO_MONEY");            break; 
      case 10020: return("TRADE_RETCODE_PRICE_CHANGED");       break; 
      case 10021: return("TRADE_RETCODE_PRICE_OFF");           break; 
      case 10022: return("TRADE_RETCODE_INVALID_EXPIRATION");  break; 
      case 10023: return("TRADE_RETCODE_ORDER_CHANGED");       break; 
      case 10024: return("TRADE_RETCODE_TOO_MANY_REQUESTS");   break; 
      case 10025: return("TRADE_RETCODE_NO_CHANGES");          break; 
      case 10026: return("TRADE_RETCODE_SERVER_DISABLES_AT");  break; 
      case 10027: return("TRADE_RETCODE_CLIENT_DISABLES_AT");  break; 
      case 10028: return("TRADE_RETCODE_LOCKED");              break; 
      case 10029: return("TRADE_RETCODE_FROZEN");              break; 
      case 10030: return("TRADE_RETCODE_INVALID_FILL");        break; 
      case 10031: return("TRADE_RETCODE_CONNECTION");          break; 
      case 10032: return("TRADE_RETCODE_ONLY_REAL");           break; 
      case 10033: return("TRADE_RETCODE_LIMIT_ORDERS");        break; 
      case 10034: return("TRADE_RETCODE_LIMIT_VOLUME");        break; 
      case 10035: return("TRADE_RETCODE_INVALID_ORDER");       break; 
      case 10036: return("TRADE_RETCODE_POSITION_CLOSED");     break; 
      case 10038: return("TRADE_RETCODE_INVALID_CLOSE_VOLUME");break; 
      case 10039: return("TRADE_RETCODE_CLOSE_ORDER_EXIST");   break; 
      case 10040: return("TRADE_RETCODE_LIMIT_POSITIONS");     break;  
      case 10041: return("TRADE_RETCODE_REJECT_CANCEL");       break; 
      case 10042: return("TRADE_RETCODE_LONG_ONLY");           break;
      case 10043: return("TRADE_RETCODE_SHORT_ONLY");          break;
      case 10044: return("TRADE_RETCODE_CLOSE_ONLY");          break;
      
      default: 
         return("TRADE_RETCODE_UNKNOWN="+IntegerToString(retcode)); 
         break; 
   } 
}
  
//+------------------------------------------------------------------+
//| Get error message by error id                                    |
//+------------------------------------------------------------------+ 
string GetErrorID(int error){

   switch(error){ 
      case 0:     return("ERR_SUCCESS");                       break; 
      case 4301:  return("ERR_MARKET_UNKNOWN_SYMBOL");         break;  
      case 4303:  return("ERR_MARKET_WRONG_PROPERTY");         break;
      case 4752:  return("ERR_TRADE_DISABLED");                break;
      case 4753:  return("ERR_TRADE_POSITION_NOT_FOUND");      break;
      case 4754:  return("ERR_TRADE_ORDER_NOT_FOUND");         break; 
      // Custom errors
      case 65537: return("ERR_DESERIALIZATION");               break;
      case 65538: return("ERR_WRONG_ACTION");                  break;
      case 65539: return("ERR_WRONG_ACTION_TYPE");             break;
      
      default: 
         return("ERR_CODE_UNKNOWN="+IntegerToString(error)); 
         break; 
   } 
}