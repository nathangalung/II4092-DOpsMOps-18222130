// WebSocket connection manager.
package websocket

import (
	"sync"

	"github.com/gofiber/fiber/v2"
	ws "github.com/gofiber/websocket/v2"
)

// Client represents a websocket client.
type Client struct {
	Conn     *ws.Conn
	Username string
	Role     string
}

// Manager manages websocket connections.
type Manager struct {
	clients    map[*Client]bool
	register   chan *Client
	unregister chan *Client
	broadcast  chan []byte
	mu         sync.RWMutex
	shutdown   chan struct{}
}

// NewManager creates websocket manager.
func NewManager() *Manager {
	return &Manager{
		clients:    make(map[*Client]bool),
		register:   make(chan *Client),
		unregister: make(chan *Client),
		broadcast:  make(chan []byte, 256),
		shutdown:   make(chan struct{}),
	}
}

// Run starts the manager loop.
func (m *Manager) Run() {
	for {
		select {
		case client := <-m.register:
			m.mu.Lock()
			m.clients[client] = true
			m.mu.Unlock()

		case client := <-m.unregister:
			m.mu.Lock()
			if _, ok := m.clients[client]; ok {
				delete(m.clients, client)
				if client.Conn != nil {
					client.Conn.Close()
				}
			}
			m.mu.Unlock()

		case message := <-m.broadcast:
			m.mu.RLock()
			for client := range m.clients {
				if client.Conn == nil {
					continue
				}
				err := client.Conn.WriteMessage(ws.TextMessage, message)
				if err != nil {
					client.Conn.Close()
					delete(m.clients, client)
				}
			}
			m.mu.RUnlock()

		case <-m.shutdown:
			m.mu.Lock()
			for client := range m.clients {
				if client.Conn != nil {
					client.Conn.Close()
				}
				delete(m.clients, client)
			}
			m.mu.Unlock()
			return
		}
	}
}

// Shutdown stops the manager.
func (m *Manager) Shutdown() {
	close(m.shutdown)
}

// Broadcast sends message to all clients.
func (m *Manager) Broadcast(message []byte) {
	m.broadcast <- message
}

// Handler returns websocket handler.
func Handler(manager *Manager) fiber.Handler {
	return ws.New(func(c *ws.Conn) {
		username := c.Locals("username").(string)
		role := c.Locals("role").(string)

		client := &Client{
			Conn:     c,
			Username: username,
			Role:     role,
		}

		manager.register <- client

		defer func() {
			manager.unregister <- client
		}()

		for {
			_, _, err := c.ReadMessage()
			if err != nil {
				break
			}
		}
	})
}
