import type { CreateOrderPayload, Order, PaginatedOrders, Stats, User } from '../types'

const BASE = '/api'

function getToken(): string | null {
  return localStorage.getItem('token')
}

async function request<T>(path: string, options: RequestInit = {}): Promise<T> {
  const token = getToken()
  const res = await fetch(`${BASE}${path}`, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...options.headers,
    },
  })

  if (!res.ok) {
    const body = await res.json().catch(() => ({ detail: res.statusText }))
    throw new Error(body.detail ?? `Request failed: ${res.status}`)
  }

  if (res.status === 204) return undefined as T
  return res.json()
}

// ── Auth ───────────────────────────────────────────────────

export async function register(full_name: string, email: string, password: string) {
  const data = await request<{ access_token: string }>('/auth/register', {
    method: 'POST',
    body: JSON.stringify({ full_name, email, password }),
  })
  localStorage.setItem('token', data.access_token)
}

export async function login(email: string, password: string) {
  const data = await request<{ access_token: string }>('/auth/login', {
    method: 'POST',
    body: JSON.stringify({ email, password }),
  })
  localStorage.setItem('token', data.access_token)
}

export async function logout() {
  await request('/auth/logout', { method: 'POST' }).catch(() => {})
  localStorage.removeItem('token')
}

export async function getMe(): Promise<User> {
  return request<User>('/auth/me')
}

// ── Orders ─────────────────────────────────────────────────

export async function getOrders(page = 1, pageSize = 10, status?: string): Promise<PaginatedOrders> {
  const params = new URLSearchParams({ page: String(page), page_size: String(pageSize) })
  if (status) params.append('status', status)
  return request<PaginatedOrders>(`/orders?${params}`)
}

export async function createOrder(payload: CreateOrderPayload): Promise<Order> {
  return request<Order>('/orders', { method: 'POST', body: JSON.stringify(payload) })
}

export async function updateOrderStatus(id: string, status: string): Promise<Order> {
  return request<Order>(`/orders/${id}`, { method: 'PUT', body: JSON.stringify({ status }) })
}

export async function cancelOrder(id: string): Promise<void> {
  return request<void>(`/orders/${id}`, { method: 'DELETE' })
}

// ── Stats ──────────────────────────────────────────────────

export async function getStats(): Promise<Stats> {
  return request<Stats>('/stats')
}
