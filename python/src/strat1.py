from contract import *
from threading import *
from time import *
from math import *
from datetime import *

class Strat1(Thread):

    # params = [stck, N, kdown, kup, pose, risk, ordertimout, barsize]
    def __init__(self, params):
        self.c = Stock(params[0])
        self.state = "CLOSED"
        self.data = []
        Thread.__init__(self)
        self.daemon = True

        # strat param
        self.N = params[1]
        self.kdown = params[2]
        self.kup = params[3]
        self.originpose = float(params[4])
        self.pose = float(params[4])
        self.risk = float(params[5])

        self.ordertimeout = timedelta(seconds=params[6])
        self.barsize = timedelta(seconds=params[7])


    def __del__(self):
       pass 

    def run(self):

        sleep(5)
        print "Start"

        # first the new data
        newdata = dict()
        newdata["open"] = newdata["high"] = newdata["low"] = newdata["close"] = self.c["mktdata"]["LAST PRICE"]
        newdata["start"] = datetime.now()

        money = self.pose

        while True:
          
            #update the OHLCV

            newdata["close"] = self.c["mktdata"]["LAST PRICE"]
            if newdata["close"] > newdata["high"]:
                newdata["high"] = newdata["close"]

            if newdata["close"] > newdata["low"]:
                newdata["low"] = newdata["close"]


            # first compute the mean (ema on N)
            try:
                alpha = 2.0/(self.N+1)
                newdata["mean"] = newdata["close"] * alpha + (1 - alpha) * self.data[0]["mean"]
            except Exception as inst:
                newdata["mean"] = newdata["close"]

            # then we compute the sigma, between 
            msum = 0
            try:

                for i in range(0,self.N-1):
                    msum += (self.data[i]["close"] - self.data[i]["mean"])**2
            except:
                pass

            msum += (newdata["close"] - newdata["mean"])**2
            
            msum = sqrt(msum)

            newdata["stdev"] = msum

            # we compute the current k
            try:
                newdata["k"] = (newdata["close"] - newdata["mean"])/newdata["stdev"]
            except:
                newdata["k"] = 0
    
            # if we are closed and the price number of sigma is < kdown we buy
            try:
                if self.state == "CLOSED" and newdata["k"] < self.kdown:
                    self.state = "OPENING"
                    openorder = self.c.order(orderty = "LMT", quantity = int(money / newdata["close"]))
                    openingtime = datetime.now()
                    print "CLOSED --> OPENING"
            except Exception as inst:
                print inst
                self.state = "CLOSED"
                pass
            
            # if we are opening, and that the position is > 0, it means that we are open
            if self.state == "OPENING" and self.c["position"] > 0:
                self.state = "OPENED"
                money += self.c["ordervalue"](openorder)
                print "OPENING --> OPENED"
                
            # if we hit the timeout, cancel it and retry
            if self.state == "OPENING" and (openingtime + self.ordertimeout) < datetime.now():
                self.c.cancel()
                openorder = self.c.order(orderty = "LMT", quantity = int(money / newdata["close"]))
                openingtime = datetime.now()
                print "OPENING --> OPENING (time out)"

            # if we are opened, we leave if: 1) we are > kup, 2) we loose risk% of our pose 
            if self.state == "OPENED":
                    
                if newdata["k"] > self.kup and self.c["upnl"] > 0:
                    self.state = "CLOSING"
                    closeorder = self.c.close(orderty = "LMT")
                    closingtime = datetime.now()
                    print "OPENED --> CLOSING (stopgain)"

                elif self.c["upnl"] < -(self.risk * self.pose):
                    self.state = "CLOSING"
                    closeorder = self.c.close(orderty = "LMT")
                    closingtime = datetime.now()
                    print "OPENED --> CLOSING (stoploss: " + str(self.c["upnl"]) + " < " + str(- (self.risk * self.pose)) + ")"

            if self.state == "CLOSING" and self.c["position"] == 0:
                self.state = "CLOSED"
                money += self.c["ordervalue"](closeorder)
                print "CLOSING --> CLOSED (money = " + str(money) + ")"

            if self.state == "CLOSING" and closingtime + self.ordertimeout < datetime.now():
                self.c.cancel()
                closeorder = self.c.close(orderty = "LMT")
                closingtime = datetime.now()                
                print "CLOSING --> CLOSING (timeout)"

            # finally we insert the newdata if the bar size is reached
            if datetime.now() > newdata["start"] + self.barsize:

                #print newdata
                
                self.data.insert(0, newdata)

                # we remove elements in the list as they are not needed
                if len(self.data) > self.N:
                    self.data.pop()

                # we create the new bar
                newdata = dict()
                newdata["open"] = newdata["high"] = newdata["low"] = newdata["close"] = self.c["mktdata"]["LAST PRICE"]
                newdata["start"] = datetime.now()


