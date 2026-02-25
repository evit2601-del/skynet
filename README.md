# skynetvpn

SkynetVPN is a VPN service with a RESTful API for managing connections, users, and server configurations.

## API Endpoints

### Authentication

#### POST `/api/auth/login`
Authenticate a user and receive a session token.

**Request Body:**
```json
{
  "username": "string",
  "password": "string"
}
```

**Response:**
```json
{
  "token": "string",
  "expires_at": "ISO 8601 datetime"
}
```

#### POST `/api/auth/logout`
Invalidate the current session token.

**Headers:**
- `Authorization: Bearer <token>`

**Response:**
```json
{
  "message": "Logged out successfully"
}
```

---

### Servers

#### GET `/api/servers`
List all available VPN servers.

**Headers:**
- `Authorization: Bearer <token>`

**Response:**
```json
[
  {
    "id": "string",
    "name": "string",
    "country": "string",
    "ip": "string",
    "status": "online | offline | maintenance"
  }
]
```

#### GET `/api/servers/{id}`
Get details for a specific VPN server.

**Headers:**
- `Authorization: Bearer <token>`

**Path Parameters:**
- `id` — Server ID

**Response:**
```json
{
  "id": "string",
  "name": "string",
  "country": "string",
  "ip": "string",
  "status": "online | offline | maintenance",
  "load": "number (0–100)"
}
```

---

### Connections

#### POST `/api/connections`
Start a VPN connection to a server.

**Headers:**
- `Authorization: Bearer <token>`

**Request Body:**
```json
{
  "server_id": "string",
  "protocol": "wireguard | openvpn"
}
```

**Response:**
```json
{
  "connection_id": "string",
  "server_id": "string",
  "status": "connecting",
  "created_at": "ISO 8601 datetime"
}
```

#### GET `/api/connections/{id}`
Get the status of an active connection.

**Headers:**
- `Authorization: Bearer <token>`

**Path Parameters:**
- `id` — Connection ID

**Response:**
```json
{
  "connection_id": "string",
  "server_id": "string",
  "status": "connecting | connected | disconnected",
  "created_at": "ISO 8601 datetime"
}
```

#### DELETE `/api/connections/{id}`
Terminate an active VPN connection.

**Headers:**
- `Authorization: Bearer <token>`

**Path Parameters:**
- `id` — Connection ID

**Response:**
```json
{
  "message": "Connection terminated"
}
```

---

### Users

#### GET `/api/users/me`
Get the current authenticated user's profile.

**Headers:**
- `Authorization: Bearer <token>`

**Response:**
```json
{
  "id": "string",
  "username": "string",
  "email": "string",
  "plan": "free | pro | enterprise",
  "created_at": "ISO 8601 datetime"
}
```

#### PATCH `/api/users/me`
Update the current user's profile.

**Headers:**
- `Authorization: Bearer <token>`

**Request Body (all fields optional):**
```json
{
  "email": "string",
  "password": "string"
}
```

**Response:**
```json
{
  "id": "string",
  "username": "string",
  "email": "string",
  "plan": "free | pro | enterprise",
  "updated_at": "ISO 8601 datetime"
}
```

---

## Error Responses

All endpoints return errors in the following format:

```json
{
  "error": "string",
  "code": "number"
}
```

| HTTP Status | Meaning                        |
|-------------|-------------------------------|
| 400         | Bad Request                   |
| 401         | Unauthorized                  |
| 403         | Forbidden                     |
| 404         | Not Found                     |
| 500         | Internal Server Error         |
