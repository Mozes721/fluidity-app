package solana

import (
	"encoding/json"
	"fmt"

	"github.com/gorilla/websocket"
)

type (
	SolanaRpcBody struct {
		JsonRpc string      `json:"jsonrpc"`
		Method  string      `json:"method"`
		Params  interface{} `json:"params"`
		Id      string      `json:"id"`
	}

	ProgramSubscribeParams [2]interface{}

	ProgramSubscribeParamsFilters struct {
		Encoding   string `json:"encoding"`
		Commitment string `json:"commitment"`
	}

	SubscriptionResponse struct {
		Jsonrpc string `json:"jsonrpc"`
		Result  int    `json:"result,omitempty"`
		Id      int    `json:"method"`
		Error   struct {
			Code    int    `json:"code"`
			Message string `json:"message"`
		} `json:"error"`
	}

	ProgramSubscribeResponse struct {
		Jsonrpc string `json:"jsonrpc"`
		Method  string `json:"method"`
		Params  struct {
			Result       ProgramNotification `json:"result"`
			Subscription int                 `json:"subscription"`
		} `json:"params"`
	}

	ProgramNotification struct {
		Context struct {
			Slot int `json:"slot"`
		} `json:"context"`
		Value struct {
			Pubkey  string `json:"pubkey"`
			Account struct {
				Lamports   int       `json:"lamports"`
				Data       [2]string `json:"data"`
				Owner      string    `json:"owner"`
				Executable bool      `json:"executable"`
				RentEpoch  int       `json:"rentEpoch"`
			} `json:"account"`
		} `json:"value"`
	}
)

type Subscription struct {
	requestCloseChan chan struct{}
}

// SubscribeProgram subscribes to changes to acounts owned by a program
func SubscribeProgram(url, programId string, messageChan chan ProgramNotification, errChan chan error) (*Subscription, error) {
	conn, _, err := websocket.DefaultDialer.Dial(url, nil)

	if err != nil {
		return nil, fmt.Errorf("Error dialling the solana websocket: %w", err)
	}

	// user requested close
	requestCloseChan := make(chan struct{})

	go func() {
		// read logs
		var (
			rawMessageChan   = make(chan []byte)
			rawErrChan       = make(chan error)
			socketClosedChan = make(chan struct{})
		)

		defer conn.Close()

		programSubscriptionParams := ProgramSubscribeParams{
			programId,
			ProgramSubscribeParamsFilters{
				Encoding:   "base64",
				Commitment: "finalized",
			},
		}

		programSubscriptionBody := SolanaRpcBody{
			JsonRpc: "2.0",
			Id:      "1",
			Method:  "programSubscribe",
			Params:  programSubscriptionParams,
		}

		// subscribe to the events
		_, err := subscribe(programSubscriptionBody, conn)

		if err != nil {
			errChan <- fmt.Errorf("Failed to subscribe to solana data acc: %w", err)
			return
		}

		// read messages into a channel, close the websocket to stop this
		go func() {
			defer close(socketClosedChan)

			for {
				_, msg, err := conn.ReadMessage()

				if err != nil {
					rawErrChan <- fmt.Errorf("Error reading from the solana websocket: %w", err)
					return
				}

				rawMessageChan <- msg
			}
		}()

		for {
			select {
			case m := <-rawMessageChan:

				// decode the message

				var res ProgramSubscribeResponse

				if err := json.Unmarshal(m, &res); err != nil {
					errChan <- fmt.Errorf("Error parsing a solana websocket message: %w", err)
					return
				}

				messageChan <- res.Params.Result

			case e := <-rawErrChan:
				errChan <- e
				return

			case <-requestCloseChan:
				err := conn.WriteMessage(
					websocket.CloseMessage,
					websocket.FormatCloseMessage(websocket.CloseNormalClosure, ""),
				)

				if err != nil {
					errChan <- fmt.Errorf("Error requesting websocket close: %w", err)
					return
				}

				// wait for the socket to close
				select {
				case <-socketClosedChan:
				}

				return
			}
		}
	}()

	sub := Subscription{
		requestCloseChan: requestCloseChan,
	}

	return &sub, nil
}

// send a subscription message and wait for the response
// this reads from the websocket, you must call this before
// reading from it elsewhere
func subscribe(message interface{}, conn *websocket.Conn) (int, error) {
	messageBytes, err := json.Marshal(message)

	if err != nil {
		return 0, fmt.Errorf("Failed to serialize message to JSON: %w", err)
	}

	err = conn.WriteMessage(websocket.TextMessage, messageBytes)

	if err != nil {
		return 0, fmt.Errorf("Error sending subscription message: %w", err)
	}

	var subscriptionRes SubscriptionResponse

	if err := conn.ReadJSON(&subscriptionRes); err != nil {
		return 0, fmt.Errorf("Error reading subscription response: %w", err)
	}

	if subscriptionRes.Error.Message != "" {
		err := fmt.Errorf("Error subscribing to solana logs: %s", subscriptionRes.Error.Message)
		return 0, err
	}

	return subscriptionRes.Id, nil
}

// Close closes a solana websocket subscription
func (s Subscription) Close() {
	s.requestCloseChan <- struct{}{}
}