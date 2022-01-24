from abc import ABC, abstractmethod
import math


class PriceController(ABC):
    """An abstract price controller that modulates price based on sales rate"""
        
    @abstractmethod
    def get_quote(self, block_delta):
        """Get price quote block_delta blocks after last sheet sale"""
        pass
    
    @abstractmethod
    def purchase_sheet(self, block_delta):
        """Purchase sheet block_delta blocks after last sale"""
        pass
    
    @abstractmethod 
    def get_ems(self, block_delta): 
        """Get EMS value block_delta blocks after last sale"""
        pass 
    
    @abstractmethod 
    def reset_state(self): 
        """Reset back to initial state """
        pass 
    
class CRISP(PriceController):
    """
    A price controller, that adjusts price upwards on purchases, and downwards slowly over time  
    
    Whenever there is a new purchase, and EMS is above target, the update rule is: 
    new_price = old_price * (1 + mismatch_ratio * price_speed)
    where mismatch_ratio = current_ems_rate / targe_ems rate
    
    When EMS is below target, price decays according to: 
    new_price = old_price * e^{-time_since_last_update/price_halflife }
    """
    
    def __init__(self, sale_halflife=100, target_blocks_per_sale=100, price_speed=1, price_halflife=100):
        ## formula for translating between target blocks per sale and target ems provided in whitepaper 
        self.target_ems = 1 / (1 - 2 ** (-target_blocks_per_sale / sale_halflife))
        self.current_ems = self.target_ems
        self.decay_start_block = 0
        self.next_starting_price = 100
        
        self.target_blocks_per_sale = target_blocks_per_sale
        self.sale_halflife = sale_halflife
        self.price_speed = price_speed
        self.price_halflife = price_halflife
        
    
    def get_ems(self, block_delta): 
        weight_on_prev = 2 ** (-block_delta/self.sale_halflife)
        return self.current_ems * weight_on_prev
        
    
    def get_quote(self, block_delta): 
        decay_delta = block_delta - self.decay_start_block
        if decay_delta > 0: 
            return self.next_starting_price * math.exp(-decay_delta / self.price_halflife)
        else: 
            return self.next_starting_price
    
    def get_next_starting_price(self, last_purchase_price):
        mismatch_ratio = self.get_ems(0) / self.target_ems
        if mismatch_ratio > 1:
            return last_purchase_price * (1 + mismatch_ratio * self.price_speed)
        else: 
            return last_purchase_price

    ## price decay only starts after mismatch ratio falls below one     
    def get_decay_start_block(self):
        mismatch_ratio = self.current_ems/self.target_ems
        ## start decay at current timestap 
        if (mismatch_ratio < 1):
            return 0
        else: 
            return math.ceil(self.sale_halflife * math.log(mismatch_ratio, 2))
        
    def purchase_sheet(self, block_delta):
        current_ems = self.get_ems(block_delta)                                          
        current_price = self.get_quote(block_delta)
        self.current_ems = current_ems + 1
        self.next_starting_price = self.get_next_starting_price(current_price)
        self.decay_start_block = self.get_decay_start_block()
                             
    def reset_state(self):
        self.current_ems = self.target_ems
        self.next_starting_price = 100
        self.decay_start_block = 0
