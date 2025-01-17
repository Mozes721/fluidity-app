// Copyright 2022 Fluidity Money. All rights reserved. Use of this
// source code is governed by a GPL-style license that can be found in the
// LICENSE.md file.

package main

import (
	"strconv"
	"time"

	"github.com/fluidity-money/fluidity-app/lib/log"
	"github.com/fluidity-money/fluidity-app/lib/queues/ethereum"
	"github.com/fluidity-money/fluidity-app/lib/queues/user-actions"
	ethereumTypes "github.com/fluidity-money/fluidity-app/lib/types/ethereum"
	"github.com/fluidity-money/fluidity-app/lib/types/network"
	"github.com/fluidity-money/fluidity-app/lib/util"

	"github.com/fluidity-money/fluidity-app/cmd/microservice-ethereum-user-actions/lib"
)

const (
	// EnvFilterAddress to use to find events published by this contract
	EnvFilterAddress = `FLU_ETHEREUM_CONTRACT_ADDR`

	// EnvTokenShortName to use when identifying user actions tracked using
	// this microservice
	EnvTokenShortName = `FLU_ETHEREUM_TOKEN_NAME`

	// EnvTokenDecimals to use when sharing user actions made with this token
	// to any downstream consumers who might make a conversion to a float for
	// user representation
	EnvTokenDecimals = `FLU_ETHEREUM_TOKEN_DECIMALS`

	// EnvNetwork to track (ethereum or arbitrum) in this microservice
	EnvNetwork = `FLU_ETHEREUM_NETWORK`

	topicUserActions = user_actions.TopicUserActionsEthereum
)

func main() {
	var (
		filterAddress_ = util.GetEnvOrFatal(EnvFilterAddress)
		tokenShortName = util.GetEnvOrFatal(EnvTokenShortName)
		tokenDecimals_ = util.GetEnvOrFatal(EnvTokenDecimals)
		network__      = util.GetEnvOrFatal(EnvNetwork)
	)

	filterAddress := ethereumTypes.AddressFromString(filterAddress_)

	tokenDecimals, err := strconv.Atoi(tokenDecimals_)

	if err != nil {
		log.Fatal(func(k *log.Log) {
			k.Format(
				"Failed to convert %#v to a number!",
				tokenDecimals_,
			)

			k.Payload = err
		})
	}

	network_, err := network.ParseEthereumNetwork(network__)

	if err != nil {
		log.Fatal(func(k *log.Log) {
			k.Format(
				"Failed to parse Ethereum network (%#v) in env %v!",
				network__,
				EnvNetwork,
			)

			k.Payload = err
		})
	}

	ethereum.Logs(func(ethLog ethereum.Log) {
		var (
			transactionHash = ethLog.TxHash
			logTopics       = ethLog.Topics
			logData         = ethLog.Data
			logAddress      = ethLog.Address
			logIndex        = ethLog.Index
		)

		log.Debugf(
			"The log address is %v, expecting %v!",
			logAddress,
			filterAddress,
		)

		if logAddress != filterAddress {
			return
		}

		log.Debug(func(k *log.Log) {
			k.Format(
				"The number of log topics is %v, expecting more than 2!",
				len(logTopics),
			)
		})

		if len(logTopics) < 2 {
			return
		}

		var (
			topicHead      = logTopics[0].String()
			topicRemaining = logTopics[1:]
		)

		// handle the respective signatures, each function crashes if bad input

		time := time.Now()

		eventClassification, err := microservice_user_actions.ClassifyEventSignature(
			topicHead,
		)

		if err != nil {
			log.Debugf(
				"Didn't decode an event signature on the wire. %v",
				err,
			)

			return
		}

		switch eventClassification {

		case microservice_user_actions.EventTransfer:
			log.Debugf(
				"Handling a transfer event, topic head is %#v",
				topicHead,
			)

			handleTransfer(
				network_,
				transactionHash,
				topicRemaining,
				logData,
				time,
				tokenShortName,
				tokenDecimals,
				logIndex,
			)

		case microservice_user_actions.EventMintFluid:
			log.Debugf(
				"Handling a minting event, topic head %#v!",
				topicHead,
			)

			handleMint(
				network_,
				transactionHash,
				topicRemaining,
				logData,
				time,
				tokenShortName,
				tokenDecimals,
			)

		case microservice_user_actions.EventBurnFluid:
			log.Debugf(
				"Handling a burning event, topic head %#v!",
				topicHead,
			)

			handleBurn(
				network_,
				transactionHash,
				topicRemaining,
				logData,
				time,
				tokenShortName,
				tokenDecimals,
			)

		default:
			panic(
				"Failed to identify a user action that didn't cause an error!",
			)
		}
	})
}
