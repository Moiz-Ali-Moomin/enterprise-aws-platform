export interface User {
  id: string
  email: string
  full_name: string
  is_active: boolean
  created_at: string
}

export type OrderStatus = 'pending' | 'processing' | 'completed' | 'cancelled'

export interface Order {
  id: string
  user_id: string
  product_name: string
  quantity: number
  unit_price: number
  total_amount: number
  status: OrderStatus
  notes: string | null
  created_at: string
  updated_at: string
}

export interface PaginatedOrders {
  items: Order[]
  total: number
  page: number
  page_size: number
  total_pages: number
}

export interface Stats {
  total_orders: number
  pending: number
  processing: number
  completed: number
  cancelled: number
  total_revenue: number
  this_month_orders: number
  this_month_revenue: number
}

export interface CreateOrderPayload {
  product_name: string
  quantity: number
  unit_price: number
  notes?: string
}
