var BasicMathLib = artifacts.require("ethereum-libraries-basic-math/contracts/BasicMathLib.sol");
var TokenLib = artifacts.require("ethereum-libraries-token/contracts/TokenLib.sol");
var CrowdsaleToken = artifacts.require("ethereum-libraries-token/contracts/CrowdsaleToken.sol");
var DirectCrowdsaleLib = artifacts.require("./DirectCrowdsaleLib.sol");

var CrowdsaleTestTokenZeroD = artifacts.require("./CrowdsaleTestTokenZeroD");
var DirectCrowdsaleTestZeroD = artifacts.require("./DirectCrowdsaleTestZeroD");

module.exports = function(deployer, network, accounts) {
  deployer.deploy(BasicMathLib,{overwrite: false});
  deployer.link(BasicMathLib, TokenLib);
  deployer.deploy(TokenLib, {overwrite: false});
  deployer.link(TokenLib, CrowdsaleToken);
  deployer.link(BasicMathLib,DirectCrowdsaleLib);
  deployer.link(TokenLib,DirectCrowdsaleLib);
  deployer.deploy(DirectCrowdsaleLib, {overwrite:false});

  if(network === "development" || network === "coverage"){
    deployer.link(TokenLib,CrowdsaleTestTokenZeroD);
    deployer.link(DirectCrowdsaleLib, DirectCrowdsaleTestZeroD);

    // startTime 3 days + 1 hour in the future
    var startTime = (Math.floor((new Date().valueOf()/1000))) + 262800;
    // first price step in 7 days
    var stepOne = startTime + 604800;
    // second price step in 14 days
    var stepTwo = stepOne + 604800;
    // endTime in 30 days
    var endTime = startTime + 2592000;
    deployer.deploy(CrowdsaleTestTokenZeroD,
                    accounts[0],
                    "Zero Decimals",
                    "ZERO",
                    0,
                    50000000,
                    false,
                    {from:accounts[4]})
    .then(function() {
      console.log(CrowdsaleTestTokenZeroD.address);
      var purchaseData =[startTime,900,
                         stepOne,675,
                         stepTwo,450];
 	    return deployer.deploy(DirectCrowdsaleTestZeroD,
                             accounts[0],
                             purchaseData,
                             endTime,
                             50,
                             CrowdsaleTestTokenZeroD.address,
                             {from:accounts[4]})
    });
  }
};
