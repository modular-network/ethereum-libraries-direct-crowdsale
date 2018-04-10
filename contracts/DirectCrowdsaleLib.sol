pragma solidity 0.4.21;

/**
 * @title DirectCrowdsaleLib
 * @author Modular Inc, https://modular.network
 *
 * version 3.0.0
 * Copyright (c) 2017 Modular Inc
 * The MIT License (MIT)
 * https://github.com/Modular-Network/ethereum-libraries/blob/master/LICENSE
 *
 * The DirectCrowdsale Library provides functionality to create a initial coin offering
 * for a standard token sale with high supply where there is a direct ether to
 * token transfer.
 *
 * Modular provides smart contract services and security reviews for contract
 * deployments in addition to working on open source projects in the Ethereum
 * community. Our purpose is to test, document, and deploy reusable code onto the
 * blockchain and improve both security and usability. We also educate non-profits,
 * schools, and other community members about the application of blockchain
 * technology. For further information: modular.network
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
 * OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

import "ethereum-libraries-basic-math/contracts/BasicMathLib.sol";
import "ethereum-libraries-token/contracts/CrowdsaleToken.sol";

library DirectCrowdsaleLib {
  using BasicMathLib for uint256;

  struct DirectCrowdsaleStorage {

    address owner;     //owner of the crowdsale

  	uint256 tokensPerEth;  //number of tokens received per ether
  	uint256 startTime; //ICO start time, timestamp
  	uint256 endTime; //ICO end time, timestamp automatically calculated
    uint256 ownerBalance; //owner wei Balance
    uint256 startingTokenBalance; //initial amount of tokens for sale
    uint256[] milestoneTimes; //Array of timestamps when token price and address cap changes
    uint8 currentMilestone; //Pointer to the current milestone
    uint8 percentBurn; //percentage of extra tokens to burn
    bool tokensSet; //true if tokens have been prepared for crowdsale

    //Maps timestamp to token price
    mapping (uint256 => uint256) tokenPrice;

    //shows how much wei an address has contributed
  	mapping (address => uint256) hasContributed;

    //For token withdraw function, maps a user address to the amount of tokens they can withdraw
  	mapping (address => uint256) withdrawTokensMap;

    // any leftover wei that buyers contributed that didn't add up to a whole token amount
    mapping (address => uint256) leftoverWei;

  	CrowdsaleToken token; //token being sold

  }

  // Indicates when an address has withdrawn their supply of tokens
  event LogTokensWithdrawn(address indexed _bidder, uint256 Amount);

  // Indicates when an address has withdrawn their supply of extra wei
  event LogWeiWithdrawn(address indexed _bidder, uint256 Amount);

  // Logs when owner has pulled eth
  event LogOwnerEthWithdrawn(address indexed owner, uint256 amount, string Msg);

  // Generic Notice message that includes and address and number
  event LogNoticeMsg(address _buyer, uint256 value, string Msg);

  // Indicates when an error has occurred in the execution of a function
  event LogErrorMsg(uint256 amount, string Msg);

  event LogTokensBought(address indexed buyer, uint256 amount);
  event LogTokenPriceChange(uint256 amount, string Msg);


  /// @dev Called by a crowdsale contract upon creation.
  /// @param self Stored crowdsale from crowdsale contract
  /// @param _owner Address of crowdsale owner
  /// @param _saleData Array of 2 item sets such that, in each 2 element
  /// set, 1 is timestamp, and 2 is price in tokens/ETH at that time
  /// @param _endTime Timestamp of sale end time
  /// @param _percentBurn Percentage of extra tokens to burn
  /// @param _token Token being sold
  function init(DirectCrowdsaleStorage storage self,
                address _owner,
                uint256[] _saleData,
                uint256 _endTime,
                uint8 _percentBurn,
                CrowdsaleToken _token)
                public
  {
    require(self.owner == 0);
    require(_saleData.length > 0);
    require((_saleData.length%2) == 0); // ensure saleData is 2-item sets
    require(_saleData[0] > (now + 2 hours));
    require(_endTime > _saleData[0]);
    require(_owner > 0);
    require(_percentBurn <= 100);
    self.owner = _owner;
    self.startTime = _saleData[0];
    self.endTime = _endTime;
    self.token = _token;
    self.percentBurn = _percentBurn;

    uint256 _tempTime;
    for(uint256 i = 0; i < _saleData.length; i += 2){
      require(_saleData[i] > _tempTime);
      require(_saleData[i + 1] > 0);
      self.milestoneTimes.push(_saleData[i]);
      self.tokenPrice[_saleData[i]] = _saleData[i + 1];
      _tempTime = _saleData[i];
    }
    self.tokensPerEth = _saleData[1];
  }

  /// @dev Called when an address wants to purchase tokens
  /// @param self Stored crowdsale from crowdsale contract
  /// @param _amount amount of wei that the buyer is sending
  /// @return true on succesful purchase
  function receivePurchase(DirectCrowdsaleStorage storage self, uint256 _amount)
                           public
                           returns (bool)
  {
    require(msg.sender != self.owner);
  	require(validPurchase(self));

  	// if the token price increase interval has passed, update the current day and change the token price
  	if ((self.milestoneTimes.length > self.currentMilestone + 1) &&
        (now > self.milestoneTimes[self.currentMilestone + 1]))
    {
        while((self.milestoneTimes.length > self.currentMilestone + 1) &&
              (now > self.milestoneTimes[self.currentMilestone + 1]))
        {
          self.currentMilestone += 1;
        }

        self.tokensPerEth = self.tokenPrice[self.milestoneTimes[self.currentMilestone]];
        emit LogTokenPriceChange(self.tokensPerEth,"Token Price has changed!");
    }

  	uint256 _numTokens; //number of tokens that will be purchased
    uint256 _newBalance; //the new balance of the owner of the crowdsale
    uint256 _weiTokens; //temp calc holder
    uint256 _leftoverWei; //wei change for purchaser
    uint256 _remainder; //temp calc holder
    bool err;

    // Find the number of tokens as a function in wei
    (err,_weiTokens) = _amount.times(self.tokensPerEth);
    require(!err);

    _numTokens = _weiTokens / 1000000000000000000;
    _remainder = _weiTokens % 1000000000000000000;
    _remainder = _remainder / self.tokensPerEth;
    _leftoverWei += _remainder;
    _amount = _amount - _remainder;
    self.leftoverWei[msg.sender] += _leftoverWei;

    // can't overflow because it is under the cap
    self.hasContributed[msg.sender] += _amount;

    assert(_numTokens <= self.token.balanceOf(this));

    // calculate the amount of ether in the owners balance
    (err,_newBalance) = self.ownerBalance.plus(_amount);
    require(!err);

    self.ownerBalance = _newBalance;   // "deposit" the amount

    // can't overflow because it will be under the cap
	  self.withdrawTokensMap[msg.sender] += _numTokens;

    //subtract tokens from owner's share
    (err,_remainder) = self.withdrawTokensMap[self.owner].minus(_numTokens);
    require(!err);
    self.withdrawTokensMap[self.owner] = _remainder;

	  emit LogTokensBought(msg.sender, _numTokens);

    return true;
  }

  /// @dev function to set tokens for the sale
  /// @param self Stored Crowdsale from crowdsale contract
  /// @return true if tokens set successfully
  function setTokens(DirectCrowdsaleStorage storage self) public returns (bool) {
    require(msg.sender == self.owner);
    require(!self.tokensSet);
    require(now < self.endTime);

    uint256 _tokenBalance;

    _tokenBalance = self.token.balanceOf(this);
    self.withdrawTokensMap[msg.sender] = _tokenBalance;
    self.startingTokenBalance = _tokenBalance;
    self.tokensSet = true;

    return true;
  }

  /// @dev function to check if a purchase is valid
  /// @param self Stored crowdsale from crowdsale contract
  /// @return true if the transaction can buy tokens
  function validPurchase(DirectCrowdsaleStorage storage self) internal returns (bool) {
    bool nonZeroPurchase = msg.value != 0;
    if (crowdsaleActive(self) && nonZeroPurchase) {
      return true;
    } else {
      emit LogErrorMsg(msg.value, "Invalid Purchase! Check start time and amount of ether.");
      return false;
    }
  }

  /// @dev Function called by purchasers to pull tokens
  /// @param self Stored crowdsale from crowdsale contract
  /// @return true if tokens were withdrawn
  function withdrawTokens(DirectCrowdsaleStorage storage self) public returns (bool) {
    bool ok;

    if (self.withdrawTokensMap[msg.sender] == 0) {
      emit LogErrorMsg(0, "Sender has no tokens to withdraw!");
      return false;
    }

    if (msg.sender == self.owner) {
      if(!crowdsaleEnded(self)){
        emit LogErrorMsg(0, "Owner cannot withdraw extra tokens until after the sale!");
        return false;
      } else {
        if(self.percentBurn > 0){
          uint256 _burnAmount = (self.withdrawTokensMap[msg.sender] * self.percentBurn)/100;
          self.withdrawTokensMap[msg.sender] = self.withdrawTokensMap[msg.sender] - _burnAmount;
          ok = self.token.burnToken(_burnAmount);
          require(ok);
        }
      }
    }

    var total = self.withdrawTokensMap[msg.sender];
    self.withdrawTokensMap[msg.sender] = 0;
    ok = self.token.transfer(msg.sender, total);
    require(ok);
    emit LogTokensWithdrawn(msg.sender, total);
    return true;
  }

  /// @dev Function called by purchasers to pull leftover wei from their purchases
  /// @param self Stored crowdsale from crowdsale contract
  /// @return true if wei was withdrawn
  function withdrawLeftoverWei(DirectCrowdsaleStorage storage self) public returns (bool) {
    if (self.leftoverWei[msg.sender] == 0) {
      emit LogErrorMsg(0, "Sender has no extra wei to withdraw!");
      return false;
    }

    var total = self.leftoverWei[msg.sender];
    self.leftoverWei[msg.sender] = 0;
    msg.sender.transfer(total);
    emit LogWeiWithdrawn(msg.sender, total);
    return true;
  }

  /// @dev send ether from the completed crowdsale to the owners wallet address
  /// @param self Stored crowdsale from crowdsale contract
  /// @return true if owner withdrew eth
  function withdrawOwnerEth(DirectCrowdsaleStorage storage self) public returns (bool) {
    if ((!crowdsaleEnded(self)) && (self.token.balanceOf(this)>0)) {
      emit LogErrorMsg(0, "Cannot withdraw owner ether until after the sale!");
      return false;
    }

    require(msg.sender == self.owner);
    require(self.ownerBalance > 0);

    uint256 amount = self.ownerBalance;
    self.ownerBalance = 0;
    self.owner.transfer(amount);
    emit LogOwnerEthWithdrawn(msg.sender,amount,"Crowdsale owner has withdrawn all funds!");

    return true;
  }

  /// @dev Gets the price and buy cap for individual addresses at the given milestone index
  /// @param self Stored Crowdsale from crowdsale contract
  /// @param timestamp Time during sale for which data is requested
  /// @return A 2-element array with 0 the timestamp, 1 the price in eth
  function getSaleData(DirectCrowdsaleStorage storage self, uint256 timestamp)
                       public
                       view
                       returns (uint256[2])
  {
    uint256[2] memory _thisData;
    uint256 index;

    while((index < self.milestoneTimes.length) && (self.milestoneTimes[index] < timestamp)) {
      index++;
    }
    if(index == 0)
      index++;

    _thisData[0] = self.milestoneTimes[index - 1];
    _thisData[1] = self.tokenPrice[_thisData[0]];
    return _thisData;
  }

  /// @dev Gets the number of tokens sold thus far
  /// @param self Stored Crowdsale from crowdsale contract
  /// @return Number of tokens sold
  function getTokensSold(DirectCrowdsaleStorage storage self) public view returns (uint256) {
    return self.startingTokenBalance - self.withdrawTokensMap[self.owner];
  }

  /// @dev function to check if the crowdsale is currently active
  /// @param self Stored crowdsale from crowdsale contract
  /// @return success
  function crowdsaleActive(DirectCrowdsaleStorage storage self) public view returns (bool) {
    return (now >= self.startTime && now <= self.endTime);
  }

  /// @dev function to check if the crowdsale has ended
  /// @param self Stored crowdsale from crowdsale contract
  /// @return success
  function crowdsaleEnded(DirectCrowdsaleStorage storage self) public view returns (bool) {
    return now > self.endTime;
  }
}
