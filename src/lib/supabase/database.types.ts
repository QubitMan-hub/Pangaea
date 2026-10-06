
export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

export type Database = {
  
  "graphql_public": {
          Tables: {
            [_ in never]: never
          }
          Views: {
            [_ in never]: never
          }
          Functions: {
            "graphql":
{ Args: { "extensions"?: Json,"operationName"?: string,"query"?: string,"variables"?: Json }; Returns: Json
                           }
          }
          Enums: {
            [_ in never]: never
          }
          CompositeTypes: {
            [_ in never]: never
          }
        },"public": {
          Tables: {
            "attention_events": {
                  Row: {
                    "created_at": string,"id": number,"kind": Database["public"]['Enums']["attention_kind"],"plot_id": string,"value": number,"visitor_id": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"id"?: never,"kind": Database["public"]['Enums']["attention_kind"],"plot_id": string,"value"?: number,"visitor_id"?: string | null
                  }
                  Update: {
                    "created_at"?: string,"id"?: never,"kind"?: Database["public"]['Enums']["attention_kind"],"plot_id"?: string,"value"?: number,"visitor_id"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "attention_events_plot_id_fkey"
      columns: ["plot_id"]
isOneToOne: false
      referencedRelation: "plots"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "attention_events_visitor_id_fkey"
      columns: ["visitor_id"]
isOneToOne: false
      referencedRelation: "users"
      referencedColumns: ["id"]
    }
                  ]
                },"comments": {
                  Row: {
                    "author_id": string,"body": string,"created_at": string,"id": string,"moderated_at": string | null,"moderation_reason": string | null,"moderation_status": Database["public"]['Enums']["moderation_status"],"plot_id": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "author_id": string,"body": string,"created_at"?: string,"id"?: string,"moderated_at"?: string | null,"moderation_reason"?: string | null,"moderation_status"?: Database["public"]['Enums']["moderation_status"],"plot_id": string,"updated_at"?: string
                  }
                  Update: {
                    "author_id"?: string,"body"?: string,"created_at"?: string,"id"?: string,"moderated_at"?: string | null,"moderation_reason"?: string | null,"moderation_status"?: Database["public"]['Enums']["moderation_status"],"plot_id"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "comments_author_id_fkey"
      columns: ["author_id"]
isOneToOne: false
      referencedRelation: "users"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "comments_plot_id_fkey"
      columns: ["plot_id"]
isOneToOne: false
      referencedRelation: "plots"
      referencedColumns: ["id"]
    }
                  ]
                },"mission_completions": {
                  Row: {
                    "created_at": string,"evidence": NonNullable<Json>,"id": string,"mission_id": string,"plot_id": string,"user_id": string,"verified": boolean
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"evidence"?: NonNullable<Json>,"id"?: string,"mission_id": string,"plot_id": string,"user_id": string,"verified"?: boolean
                  }
                  Update: {
                    "created_at"?: string,"evidence"?: NonNullable<Json>,"id"?: string,"mission_id"?: string,"plot_id"?: string,"user_id"?: string,"verified"?: boolean
                  }
                  Relationships: [
                    {
      foreignKeyName: "mission_completions_mission_id_fkey"
      columns: ["mission_id"]
isOneToOne: false
      referencedRelation: "missions"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "mission_completions_plot_id_fkey"
      columns: ["plot_id"]
isOneToOne: false
      referencedRelation: "plots"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "mission_completions_user_id_fkey"
      columns: ["user_id"]
isOneToOne: false
      referencedRelation: "users"
      referencedColumns: ["id"]
    }
                  ]
                },"missions": {
                  Row: {
                    "created_at": string,"description": string,"ends_at": string | null,"id": string,"is_sponsored": boolean,"reward_points": number,"slug": string,"starts_at": string | null,"title": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"description": string,"ends_at"?: string | null,"id"?: string,"is_sponsored"?: boolean,"reward_points": number,"slug": string,"starts_at"?: string | null,"title": string
                  }
                  Update: {
                    "created_at"?: string,"description"?: string,"ends_at"?: string | null,"id"?: string,"is_sponsored"?: boolean,"reward_points"?: number,"slug"?: string,"starts_at"?: string | null,"title"?: string
                  }
                  Relationships: [
                    
                  ]
                },"plot_items": {
                  Row: {
                    "content": NonNullable<Json>,"created_at": string,"id": string,"moderated_at": string | null,"moderation_reason": string | null,"moderation_status": Database["public"]['Enums']["moderation_status"],"plot_id": string,"position": NonNullable<Json>,"type": Database["public"]['Enums']["plot_item_type"],"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "content": NonNullable<Json>,"created_at"?: string,"id"?: string,"moderated_at"?: string | null,"moderation_reason"?: string | null,"moderation_status"?: Database["public"]['Enums']["moderation_status"],"plot_id": string,"position"?: NonNullable<Json>,"type": Database["public"]['Enums']["plot_item_type"],"updated_at"?: string
                  }
                  Update: {
                    "content"?: NonNullable<Json>,"created_at"?: string,"id"?: string,"moderated_at"?: string | null,"moderation_reason"?: string | null,"moderation_status"?: Database["public"]['Enums']["moderation_status"],"plot_id"?: string,"position"?: NonNullable<Json>,"type"?: Database["public"]['Enums']["plot_item_type"],"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "plot_items_plot_id_fkey"
      columns: ["plot_id"]
isOneToOne: false
      referencedRelation: "plots"
      referencedColumns: ["id"]
    }
                  ]
                },"plots": {
                  Row: {
                    "base_size": number,"created_at": string,"earned_space": number,"embedding": string | null,"embedding_model": string | null,"grid_x": number | null,"grid_y": number | null,"id": string,"last_active_at": string,"owner_id": string,"region_id": string | null,"status": Database["public"]['Enums']["plot_status"],"summary": string | null,"thumbnail_url": string | null,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "base_size"?: number,"created_at"?: string,"earned_space"?: number,"embedding"?: string | null,"embedding_model"?: string | null,"grid_x"?: number | null,"grid_y"?: number | null,"id"?: string,"last_active_at"?: string,"owner_id": string,"region_id"?: string | null,"status"?: Database["public"]['Enums']["plot_status"],"summary"?: string | null,"thumbnail_url"?: string | null,"updated_at"?: string
                  }
                  Update: {
                    "base_size"?: number,"created_at"?: string,"earned_space"?: number,"embedding"?: string | null,"embedding_model"?: string | null,"grid_x"?: number | null,"grid_y"?: number | null,"id"?: string,"last_active_at"?: string,"owner_id"?: string,"region_id"?: string | null,"status"?: Database["public"]['Enums']["plot_status"],"summary"?: string | null,"thumbnail_url"?: string | null,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "plots_owner_id_fkey"
      columns: ["owner_id"]
isOneToOne: true
      referencedRelation: "users"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "plots_region_id_fkey"
      columns: ["region_id"]
isOneToOne: false
      referencedRelation: "regions"
      referencedColumns: ["id"]
    }
                  ]
                },"region_visits": {
                  Row: {
                    "first_visited_at": string,"region_id": string,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "first_visited_at"?: string,"region_id": string,"user_id": string
                  }
                  Update: {
                    "first_visited_at"?: string,"region_id"?: string,"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "region_visits_region_id_fkey"
      columns: ["region_id"]
isOneToOne: false
      referencedRelation: "regions"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "region_visits_user_id_fkey"
      columns: ["user_id"]
isOneToOne: false
      referencedRelation: "users"
      referencedColumns: ["id"]
    }
                  ]
                },"regions": {
                  Row: {
                    "center_x": number,"center_y": number,"centroid_embedding": string | null,"created_at": string,"id": string,"is_frontier": boolean,"label": string,"plot_count": number,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "center_x": number,"center_y": number,"centroid_embedding"?: string | null,"created_at"?: string,"id"?: string,"is_frontier"?: boolean,"label": string,"plot_count"?: number,"updated_at"?: string
                  }
                  Update: {
                    "center_x"?: number,"center_y"?: number,"centroid_embedding"?: string | null,"created_at"?: string,"id"?: string,"is_frontier"?: boolean,"label"?: string,"plot_count"?: number,"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"reports": {
                  Row: {
                    "created_at": string,"id": string,"reason": string,"reporter_id": string | null,"resolved_at": string | null,"resolved_by": string | null,"status": Database["public"]['Enums']["report_status"],"target_id": string,"target_type": Database["public"]['Enums']["report_target"]
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"id"?: string,"reason": string,"reporter_id"?: string | null,"resolved_at"?: string | null,"resolved_by"?: string | null,"status"?: Database["public"]['Enums']["report_status"],"target_id": string,"target_type": Database["public"]['Enums']["report_target"]
                  }
                  Update: {
                    "created_at"?: string,"id"?: string,"reason"?: string,"reporter_id"?: string | null,"resolved_at"?: string | null,"resolved_by"?: string | null,"status"?: Database["public"]['Enums']["report_status"],"target_id"?: string,"target_type"?: Database["public"]['Enums']["report_target"]
                  }
                  Relationships: [
                    {
      foreignKeyName: "reports_reporter_id_fkey"
      columns: ["reporter_id"]
isOneToOne: false
      referencedRelation: "users"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "reports_resolved_by_fkey"
      columns: ["resolved_by"]
isOneToOne: false
      referencedRelation: "users"
      referencedColumns: ["id"]
    }
                  ]
                },"staff": {
                  Row: {
                    "created_at": string,"role": Database["public"]['Enums']["staff_role"],"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"role": Database["public"]['Enums']["staff_role"],"user_id": string
                  }
                  Update: {
                    "created_at"?: string,"role"?: Database["public"]['Enums']["staff_role"],"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "staff_user_id_fkey"
      columns: ["user_id"]
isOneToOne: true
      referencedRelation: "users"
      referencedColumns: ["id"]
    }
                  ]
                },"users": {
                  Row: {
                    "created_at": string,"handle": string,"id": string,"trust_level": number,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"handle": string,"id": string,"trust_level"?: number,"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"handle"?: string,"id"?: string,"trust_level"?: number,"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                }
          }
          Views: {
            "comments_public": {
                  Row: {
                    "author_id": string | null,"body": string | null,"created_at": string | null,"id": string | null,"moderation_status": Database["public"]['Enums']["moderation_status"] | null,"plot_id": string | null
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "comments_author_id_fkey"
      columns: ["author_id"]
isOneToOne: false
      referencedRelation: "users"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "comments_plot_id_fkey"
      columns: ["plot_id"]
isOneToOne: false
      referencedRelation: "plots"
      referencedColumns: ["id"]
    }
                  ]
                },"plot_items_public": {
                  Row: {
                    "content": Json | null,"created_at": string | null,"id": string | null,"moderation_status": Database["public"]['Enums']["moderation_status"] | null,"plot_id": string | null,"position": Json | null,"type": Database["public"]['Enums']["plot_item_type"] | null,"updated_at": string | null
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "plot_items_plot_id_fkey"
      columns: ["plot_id"]
isOneToOne: false
      referencedRelation: "plots"
      referencedColumns: ["id"]
    }
                  ]
                }
          }
          Functions: {
            [_ in never]: never
          }
          Enums: {
            "attention_kind": "view"|"dwell"|"comment"|"return_visit","moderation_status": "pending"|"approved"|"rejected"|"blurred","plot_item_type": "text"|"drawing"|"image"|"link"|"code"|"webpage"|"video"|"document","plot_status": "active"|"suspended","report_status": "open"|"actioned"|"dismissed","report_target": "plot"|"plot_item"|"comment"|"user","staff_role": "moderator"|"admin"
          }
          CompositeTypes: {
            [_ in never]: never
          }
        }
}

type DatabaseWithoutInternals = Omit<Database, '__InternalSupabase'>

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
  ? (DefaultSchema["Tables"] & DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
      Row: infer R
    }
    ? R
    : never
  : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
  ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Insert: infer I
    }
    ? I
    : never
  : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
  ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Update: infer U
    }
    ? U
    : never
  : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never
> = DefaultSchemaEnumNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
  ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
  : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never
> = PublicCompositeTypeNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
  ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
  : never

export const Constants = {
  "graphql_public": {
          Enums: {
            
          }
        },"public": {
          Enums: {
            "attention_kind": ["view", "dwell", "comment", "return_visit"],"moderation_status": ["pending", "approved", "rejected", "blurred"],"plot_item_type": ["text", "drawing", "image", "link", "code", "webpage", "video", "document"],"plot_status": ["active", "suspended"],"report_status": ["open", "actioned", "dismissed"],"report_target": ["plot", "plot_item", "comment", "user"],"staff_role": ["moderator", "admin"]
          }
        }
} as const
