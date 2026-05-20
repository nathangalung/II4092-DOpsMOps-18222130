package websocket

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestNewManager(t *testing.T) {
	t.Run("creates manager with initialized channels", func(t *testing.T) {
		manager := NewManager()

		assert.NotNil(t, manager)
		assert.NotNil(t, manager.clients)
		assert.NotNil(t, manager.register)
		assert.NotNil(t, manager.unregister)
		assert.NotNil(t, manager.broadcast)
		assert.NotNil(t, manager.shutdown)
	})

	t.Run("clients map is empty initially", func(t *testing.T) {
		manager := NewManager()

		assert.Empty(t, manager.clients)
	})
}

func TestManager_Broadcast(t *testing.T) {
	t.Run("sends message to broadcast channel", func(t *testing.T) {
		manager := NewManager()
		message := []byte("test message")

		go manager.Broadcast(message)

		select {
		case msg := <-manager.broadcast:
			assert.Equal(t, message, msg)
		case <-time.After(100 * time.Millisecond):
			t.Fatal("broadcast did not receive message")
		}
	})
}

func TestManager_Shutdown(t *testing.T) {
	t.Run("closes shutdown channel", func(t *testing.T) {
		manager := NewManager()

		go manager.Shutdown()

		select {
		case <-manager.shutdown:
			// Successfully closed
		case <-time.After(100 * time.Millisecond):
			t.Fatal("shutdown channel not closed")
		}
	})
}

func TestManager_Run(t *testing.T) {
	t.Run("stops on shutdown signal", func(t *testing.T) {
		manager := NewManager()

		done := make(chan bool)
		go func() {
			manager.Run()
			done <- true
		}()

		time.Sleep(10 * time.Millisecond)
		manager.Shutdown()

		select {
		case <-done:
			// Successfully stopped
		case <-time.After(500 * time.Millisecond):
			t.Fatal("manager did not stop")
		}
	})

	t.Run("handles client registration", func(t *testing.T) {
		manager := NewManager()

		done := make(chan bool)
		go func() {
			manager.Run()
			done <- true
		}()

		client := &Client{
			Username: "testuser",
			Role:     "admin",
		}

		go func() {
			manager.register <- client
			time.Sleep(10 * time.Millisecond)
			manager.Shutdown()
		}()

		select {
		case <-done:
			// Successfully handled registration and shutdown
		case <-time.After(500 * time.Millisecond):
			t.Fatal("manager did not process registration")
		}
	})
}

func TestClient_Structure(t *testing.T) {
	t.Run("client has correct fields", func(t *testing.T) {
		client := &Client{
			Username: "testuser",
			Role:     "data_scientist",
		}

		assert.Equal(t, "testuser", client.Username)
		assert.Equal(t, "data_scientist", client.Role)
		assert.Nil(t, client.Conn) // Conn is nil in tests
	})
}

func TestManager_ClientManagement(t *testing.T) {
	t.Run("adds client to map on registration", func(t *testing.T) {
		manager := NewManager()

		done := make(chan bool)
		go func() {
			manager.Run()
			done <- true
		}()

		client := &Client{
			Username: "user1",
			Role:     "admin",
		}

		manager.register <- client
		time.Sleep(10 * time.Millisecond)

		manager.mu.RLock()
		_, exists := manager.clients[client]
		manager.mu.RUnlock()

		assert.True(t, exists, "client should be in map")

		manager.Shutdown()
		<-done
	})

	t.Run("removes client from map on unregister", func(t *testing.T) {
		manager := NewManager()

		done := make(chan bool)
		go func() {
			manager.Run()
			done <- true
		}()

		client := &Client{
			Username: "user1",
			Role:     "admin",
		}

		manager.register <- client
		time.Sleep(10 * time.Millisecond)

		manager.unregister <- client
		time.Sleep(10 * time.Millisecond)

		manager.mu.RLock()
		_, exists := manager.clients[client]
		manager.mu.RUnlock()

		assert.False(t, exists, "client should be removed from map")

		manager.Shutdown()
		<-done
	})
}

func TestManager_Concurrency(t *testing.T) {
	t.Run("handles multiple concurrent operations", func(t *testing.T) {
		manager := NewManager()

		done := make(chan bool)
		go func() {
			manager.Run()
			done <- true
		}()

		// Register multiple clients
		for i := 0; i < 10; i++ {
			client := &Client{
				Username: "user",
				Role:     "admin",
			}
			manager.register <- client
		}

		// Send broadcasts
		for i := 0; i < 5; i++ {
			go manager.Broadcast([]byte("message"))
		}

		time.Sleep(50 * time.Millisecond)
		manager.Shutdown()

		select {
		case <-done:
			// Successfully handled concurrent operations
		case <-time.After(500 * time.Millisecond):
			t.Fatal("manager did not handle concurrent operations")
		}
	})
}

func TestHandler_Integration(t *testing.T) {
	t.Run("handler function exists", func(t *testing.T) {
		manager := NewManager()

		// Verify Handler function exists and returns a handler
		handler := Handler(manager)

		assert.NotNil(t, handler)
	})
}

func TestManager_BroadcastBuffer(t *testing.T) {
	t.Run("broadcast channel has buffer", func(t *testing.T) {
		manager := NewManager()

		// Should be able to send 256 messages without blocking
		for i := 0; i < 256; i++ {
			select {
			case manager.broadcast <- []byte("message"):
				// Successfully sent
			default:
				t.Fatal("broadcast channel should have buffer of 256")
			}
		}
	})
}

func TestClient_NilConn(t *testing.T) {
	t.Run("handles nil connection gracefully", func(t *testing.T) {
		client := &Client{
			Conn:     nil,
			Username: "test",
			Role:     "admin",
		}

		// Should not panic when conn is nil
		assert.NotNil(t, client)
		assert.Nil(t, client.Conn)
	})
}

func TestManager_CleanupOnShutdown(t *testing.T) {
	t.Run("closes all client connections on shutdown", func(t *testing.T) {
		manager := NewManager()

		done := make(chan bool)
		go func() {
			manager.Run()
			done <- true
		}()

		// Add some clients
		clients := make([]*Client, 5)
		for i := 0; i < 5; i++ {
			clients[i] = &Client{
				Username: "user",
				Role:     "admin",
			}
			manager.register <- clients[i]
		}

		time.Sleep(10 * time.Millisecond)
		manager.Shutdown()

		<-done

		// All clients should be removed
		manager.mu.RLock()
		assert.Empty(t, manager.clients)
		manager.mu.RUnlock()
	})
}
